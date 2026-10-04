import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../constants/legend_constants.dart';
import '../../constants/map_constants.dart';
import '../../models/ranked_match.dart';
import '../../models/season_meta.dart';
import '../formatting/season_utils.dart';
import '../app_logger.dart';
import '../formatting/snapshot_types.dart';
import '../ranked/ranked_aggregates.dart';

/// Local SQLite store that accumulates ranked match history per UID, beyond the
/// API's rolling 100-match window. Matches are deduped by [RankedMatch.dedupKey]
/// (`uid_startSecond`), so re-fetching the same 100 matches is idempotent and
/// older matches survive as new ones push them out of the API window.
///
/// On iOS/Android the default sqflite factory is used. Tests/desktop set
/// `databaseFactory` to the FFI implementation; pass [overridePath] (e.g.
/// `inMemoryDatabasePath`) to isolate a database.
class RankedHistoryStore {
  static const _dbName = 'ranked_history.db';
  static const table = 'ranked_matches';

  /// RP snapshots - the *other* RP source (see `rp_snapshot_storage.dart`).
  /// Lives here rather than in its own database because it shares this one's
  /// lifecycle, backup envelope and per-UID scoping.
  static const snapshotTable = 'stat_snapshots';

  static const _version = 10;

  /// How long a favourite's RP snapshots are kept (see [pruneSnapshots]).
  static const favoriteSnapshotMaxAge = Duration(days: 90);

  /// How long anyone else's are kept; nothing records new readings for them, so they age.
  static const otherSnapshotMaxAge = Duration(days: 14);

  /// SQL `GLOB` shape of a real split id (`br_ranked_s29_s1`) — the SQL side
  /// of [SeasonMeta.isSplitId]. NULL, [kUnknownSeasonId], and any placeholder
  /// id upstream sends (e.g. `__other__`) all fail to match.
  static const _splitIdGlob = '*s[0-9]*_s[0-9]*';

  // Scope of the lazy season backfill: every row not yet under a real split,
  // placeholder ids included, so one can still be re-classified once its
  // real split's window is known.
  //
  // Used verbatim by both a partial index and the backfill query, which must
  // stay byte-identical or SQLite won't apply the index and the backfill falls
  // back to a full-table scan. One constant, so the two can't drift.
  static const _needsSeasonId =
      "season_id IS NULL OR season_id NOT GLOB '$_splitIdGlob'";

  final String? _overridePath;
  Database? _db;

  // The in-flight open, held only while one is running. See [_open].
  Future<Database>? _opening;

  /// Test hook: sqflite silently no-ops a duplicate open of the same path
  /// (no error, no second `onCreate`), so this counter is the only way to
  /// verify [_open]'s single-open guarantee.
  @visibleForTesting
  int openCount = 0;

  // this._overridePath can't be a named parameter here — private identifiers
  // aren't callable from outside the library, and `overridePath:` must stay
  // public for existing callers.
  // ignore: prefer_initializing_formals
  RankedHistoryStore({String? overridePath}) : _overridePath = overridePath;

  /// The open database, opening it on first use.
  ///
  /// Memoizes the in-flight *future*, not just the result - several ranked
  /// providers can resume in the same microtask drain and race into this
  /// method before `_db` is set, and a plain `if (_db != null)` check would
  /// let each one call [openDatabase] (leaked handles, possibly concurrent
  /// `onUpgrade` runs). [_opening] is assigned synchronously, before any
  /// await, so a racing caller awaits the same future instead of its own.
  Future<Database> _open() {
    final db = _db;
    if (db != null) return Future.value(db);
    // Cleared on completion (including failure) so a transient open error
    // can't pin a rejected future for every later call.
    return _opening ??= _doOpen().whenComplete(() => _opening = null);
  }

  Future<Database> _doOpen() async {
    openCount++;
    final path = _overridePath ?? await _resolveDbPath();
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $table (
            id TEXT PRIMARY KEY,
            uid TEXT NOT NULL,
            player_name TEXT,
            legend TEXT,
            game_mode TEXT,
            map_key TEXT,
            rp_change INTEGER,
            cumulative_rp INTEGER,
            rank_img TEXT,
            length_secs INTEGER,
            start_ms INTEGER,
            end_ms INTEGER,
            is_party_full INTEGER,
            trackers TEXT,
            season_id TEXT,
            kills INTEGER,
            damage INTEGER,
            edited_fields TEXT,
            excluded INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_uid_start ON $table (uid, start_ms)',
        );
        await db.execute(
          'CREATE INDEX idx_uid_season ON $table (uid, season_id)',
        );
        await db.execute(
          'CREATE INDEX idx_ranked_scope '
          'ON $table (uid, game_mode, rp_change)',
        );
        await _createSeasonBackfillIndex(db);
        await _createSnapshotTable(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        // v1 → v2: add the derived season/split column + its index. Existing
        // rows get a NULL season_id and are populated lazily by
        // [backfillSeasonIds] once season metadata is available.
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE $table ADD COLUMN season_id TEXT');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_uid_season ON $table (uid, season_id)',
          );
        }
        // v2 → v3: denormalize kills/damage out of the trackers JSON blob into
        // real columns so aggregates can SUM() them in SQL. Existing rows get
        // NULLs, filled lazily by [backfillKillsDamage].
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE $table ADD COLUMN kills INTEGER');
          await db.execute('ALTER TABLE $table ADD COLUMN damage INTEGER');
        }
        // v3 → v4: partial indexes over just the rows each lazy backfill still
        // has to touch, so those passes stop full-scanning the table on every
        // sync once the backlog is drained.
        if (oldVersion < 4) {
          await _createSeasonBackfillIndex(db);
        }
        // v4 → v5: index the ranked-scope prefix shared by every SQL aggregate
        // (uid + BATTLE_ROYALE + RP-changed), so the Lifetime queries narrow to
        // a player's ranked games instead of scanning all of their rows.
        if (oldVersion < 5) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_ranked_scope '
            'ON $table (uid, game_mode, rp_change)',
          );
        }
        // v5 → v6: hand-editable rows, and NULL kills/damage meaning "upstream
        // reported no tracker" rather than "not backfilled yet".
        //
        // The old lazy backfill and its partial index are dropped with it: its
        // predicate was `kills IS NULL OR damage IS NULL`, which every
        // legitimately unreported row now matches permanently, so the index
        // could never drain and the pass would full-scan on every sync.
        // [_repairTrackerColumns] replaces it as a one-time pass.
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE $table ADD COLUMN edited_fields TEXT');
          await db.execute('DROP INDEX IF EXISTS idx_needs_kills_damage');
          await _repairTrackerColumns(db);
        }
        // v6 → v7: one-time repair for kills/damage values outside the
        // plausible per-game range (kMaxPlausibleKills/kMaxPlausibleDamage in
        // ranked_match.dart) — almost certainly a bad upstream value, not a
        // real game. Nulled rather than zeroed (same "not reported" meaning
        // as an absent tracker) and flagged in edited_fields so a future sync
        // can't bring the bad value back. rp_change doesn't need row repair:
        // RankedMatch.isAutoExcluded leaves an implausible swing out of every
        // aggregate, computed fresh from the stored value with no migration
        // needed.
        if (oldVersion < 7) {
          await _repairImplausibleStats(db);
        }
        // v7 → v8: RP snapshots move out of an ever-growing SharedPreferences
        // JSON string into a real table. Prefs migration happens separately
        // via `migrateSnapshotsFromPrefs`, which needs SharedPreferences.
        if (oldVersion < 8) {
          await _createSnapshotTable(db);
        }
        // v8 → v9: _needsSeasonId widened to include placeholder ids, so a
        // row filed under one gets re-classified. Its partial index must
        // match byte for byte, so it's rebuilt; the next backfill does the rest.
        if (oldVersion < 9) {
          await db.execute('DROP INDEX IF EXISTS idx_needs_season_id');
          await _createSeasonBackfillIndex(db);
        }
        // v9 → v10: hand-exclude a match from every ranked calculation
        // (separate from edited_fields — see [RankedMatch.excluded]).
        // Existing rows default to 0 (included), matching a freshly synced
        // match.
        if (oldVersion < 10) {
          await db.execute(
            'ALTER TABLE $table ADD COLUMN excluded INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
    return _db!;
  }

  /// Partial index scoped to the rows the season backfill still has to touch.
  /// SQLite drops a row from a partial index the moment an UPDATE makes it stop
  /// matching the predicate, so once every legacy row is classified the index is
  /// empty and the backfill's scan touches nothing — no per-sync full table
  /// scan, and no app-side "already done" bookkeeping to maintain or reset.
  Future<void> _createSeasonBackfillIndex(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_needs_season_id '
      'ON $table (id) WHERE $_needsSeasonId',
    );
  }

  /// The RP-snapshot table. `(uid, ts_ms)` is the primary key: one reading per
  /// player per instant, so a replayed append or a re-run migration is
  /// idempotent rather than duplicating the series. That doubles as the index
  /// for every read, which is always "this player's snapshots, oldest first".
  Future<void> _createSnapshotTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $snapshotTable (
        uid TEXT NOT NULL,
        ts_ms INTEGER NOT NULL,
        rp INTEGER NOT NULL,
        season_id TEXT,
        PRIMARY KEY (uid, ts_ms)
      )
    ''');
  }

  /// Re-derives every row's [kills]/[damage] from its stored `trackers` blob,
  /// writing NULL where the blob carries no such tracker.
  ///
  /// The v2 → v3 migration and its backfill wrote 0 for an absent tracker,
  /// which is indistinguishable from a real scoreless game and drags every
  /// average down. The blob is untouched by all of that, so the true value is
  /// still recoverable for history recorded before this fix.
  Future<void> _repairTrackerColumns(Database db) async {
    final rows = await db.query(table, columns: ['id', 'trackers']);
    if (rows.isEmpty) return;
    final batch = db.batch();
    for (final r in rows) {
      final trackers = RankedMatch.fromStoredMap({
        'trackers': r['trackers'],
      }).trackers;
      batch.update(
        table,
        {
          'kills': RankedMatch.killsFrom(trackers),
          'damage': RankedMatch.damageFrom(trackers),
        },
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  /// One-time repair for existing rows whose kills/damage falls outside the
  /// plausible per-game range. See the v6 → v7 migration comment above.
  Future<void> _repairImplausibleStats(Database db) async {
    final rows = await db.query(
      table,
      columns: ['id', 'kills', 'damage', 'edited_fields'],
      where:
          'kills < 0 OR kills > $kMaxPlausibleKills OR '
          'damage < 0 OR damage > $kMaxPlausibleDamage',
    );
    if (rows.isEmpty) return;
    final batch = db.batch();
    for (final r in rows) {
      final kills = (r['kills'] as num?)?.toInt();
      final damage = (r['damage'] as num?)?.toInt();
      final badKills =
          kills != null && (kills < 0 || kills > kMaxPlausibleKills);
      final badDamage =
          damage != null && (damage < 0 || damage > kMaxPlausibleDamage);
      final flags = {
        ...decodeEditedFields(r['edited_fields']),
        if (badKills) 'kills',
        if (badDamage) 'damage',
      };
      batch.update(
        table,
        {
          if (badKills) 'kills': null,
          if (badDamage) 'damage': null,
          'edited_fields': encodeEditedFields(flags),
        },
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Runs [apply] over every row of [table] (projected to [columns] plus
  /// `id`), [batchSize] at a time, committing one [Batch] per page instead of
  /// hydrating the whole table into memory at once. Available for a future
  /// migration or repair pass on this table, which is unbounded and only
  /// grows; deliberately not applied to the existing one-time migrations
  /// above, which have already run on most installs.
  ///
  /// Pages by `id > lastId ORDER BY id`, not `LIMIT`/`OFFSET`: [apply] is
  /// expected to change rows, and an optional [where] may stop matching a row
  /// it just fixed. OFFSET pagination over a shrinking result set skips rows;
  /// paging by primary key doesn't.
  ///
  /// [apply] receives the batch to add operations to and one row; it must add
  /// to the batch but never commit it itself.
  ///
  /// Static, not an instance method: it uses no state of its own and a
  /// migration calls it from inside `onUpgrade`'s callback, with that
  /// callback's own `db` — never through [_open], which is what's calling
  /// `onUpgrade` in the first place.
  static Future<void> forEachRowInBatches(
    Database db,
    String table, {
    required List<String> columns,
    String? where,
    int batchSize = 500,
    required void Function(Batch batch, Map<String, Object?> row) apply,
  }) async {
    final projection = {'id', ...columns}.toList();
    String? lastId;
    while (true) {
      final pageWhere = [
        if (where != null) '($where)',
        if (lastId != null) 'id > ?',
      ].join(' AND ');
      final page = await db.query(
        table,
        columns: projection,
        where: pageWhere.isEmpty ? null : pageWhere,
        whereArgs: lastId != null ? [lastId] : null,
        orderBy: 'id',
        limit: batchSize,
      );
      if (page.isEmpty) break;
      final batch = db.batch();
      for (final row in page) {
        apply(batch, row);
      }
      await batch.commit(noResult: true);
      lastId = page.last['id'] as String;
      if (page.length < batchSize) break;
    }
  }

  /// Mobile's native sqflite factory returns a guaranteed-existing app
  /// databases directory. The FFI factory used on desktop instead defaults to
  /// a `.dart_tool`-relative path that only exists in a dev checkout — a
  /// packaged release binary's working directory won't have it, so opening
  /// fails with SQLITE_CANTOPEN. Resolve a real per-user app-support
  /// directory there instead, creating it if needed.
  Future<String> _resolveDbPath() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return p.join(await getDatabasesPath(), _dbName);
    }
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return p.join(dir.path, _dbName);
  }

  /// Columns a conflicting row takes from the incoming one, with no edit
  /// protection to consult.
  static const _overwrittenColumns = [
    'uid',
    'player_name',
    'game_mode',
    'cumulative_rp',
    'rank_img',
    'start_ms',
    'end_ms',
    'is_party_full',
    'trackers',
  ];

  /// Whether [column] is flagged in [editedFields] (`edited_fields` or
  /// `excluded.edited_fields`). The comma-delimited form lets membership be a
  /// plain `instr` test.
  static String _flagged(String editedFields, String column) =>
      "instr(COALESCE($editedFields, ''), ',$column,') > 0";

  /// `ON CONFLICT(id) DO UPDATE SET` body for [upsertAll] (a sync, [restore]
  /// false) and [importRows] (a backup restore, [restore] true) — built from
  /// one column list and one edit rule so the two can only differ as follows.
  ///
  /// Shared: a hand-edited column keeps its value; `season_id` only upgrades
  /// (adopts the incoming id once, if it's a real split, then never again).
  ///
  /// A sync overwrites everything else from upstream and never writes
  /// `edited_fields`, so it can't clear the flags. A restore, since a backup
  /// row can be older or less complete than the one it lands on: keeps the
  /// stored value where the backup has NULL (missing, not "clear it"); takes
  /// the backup's value, NULL included, for a column *it* flagged edited; and
  /// writes `edited_fields` as the union [importRows] pre-computes.
  static String _conflictUpdateSet({required bool restore}) {
    String incoming(String col) =>
        restore ? 'COALESCE(excluded.$col, $col)' : 'excluded.$col';
    return [
      for (final col in _overwrittenColumns) '$col = ${incoming(col)}',
      for (final f in kEditableMatchFields)
        '$f = CASE WHEN ${_flagged('edited_fields', f)} THEN $f '
            '${restore ? 'WHEN ${_flagged('excluded.edited_fields', f)} THEN excluded.$f ' : ''}'
            'ELSE ${incoming(f)} END',
      "season_id = CASE WHEN excluded.season_id GLOB '$_splitIdGlob' "
          'AND ($_needsSeasonId) THEN excluded.season_id ELSE season_id END',
      if (restore) 'edited_fields = excluded.edited_fields',
      // A restore can exclude a match but never re-include one.
      if (restore) 'excluded = MAX($table.excluded, excluded.excluded)',
    ].join(',\n          ');
  }

  /// Upsert columns in bind order; a restore also carries `excluded`.
  static const _upsertColumns = [
    'id',
    'uid',
    'player_name',
    'legend',
    'game_mode',
    'map_key',
    'rp_change',
    'cumulative_rp',
    'rank_img',
    'length_secs',
    'start_ms',
    'end_ms',
    'is_party_full',
    'trackers',
    'season_id',
    'kills',
    'damage',
    'edited_fields',
  ];

  static const _restoreColumns = [..._upsertColumns, 'excluded'];

  /// The upsert SQL for [upsertAll] (sync) or [importRows] (restore), built once, not per row.
  static String _upsertSql({required bool restore}) {
    final columns = restore ? _restoreColumns : _upsertColumns;
    return '''
        INSERT INTO $table (${columns.join(', ')})
        VALUES (${List.filled(columns.length, '?').join(', ')})
        ON CONFLICT(id) DO UPDATE SET
        ${_conflictUpdateSet(restore: restore)}
        ''';
  }

  static final _syncUpsertSql = _upsertSql(restore: false);
  static final _restoreUpsertSql = _upsertSql(restore: true);

  /// Rows per restore batch; one batch for a large history is a huge platform-channel message.
  static const _importBatchSize = 500;

  /// Inserts/updates [matches] for [uid]. Idempotent via the primary key.
  /// A match whose own uid isn't [uid] is skipped (and counted in a warning).
  ///
  /// Three groups of columns behave differently on conflict:
  ///
  /// - Most are overwritten unconditionally from the incoming row.
  /// - [kEditableMatchFields] keep a hand-corrected value and are otherwise
  ///   overwritten. `edited_fields` itself is omitted from the SET clause, so a
  ///   sync can never clear the flags that protect them.
  /// - [season_id] only ever *upgrades* — a row not yet under a real split
  ///   (NULL, [kUnknownSeasonId], or a placeholder id) adopts the
  ///   freshly-derived id when [seasons] yields a real one, but a row already
  ///   carrying a real split id is never touched again, even if this call's
  ///   [seasons] is empty or incomplete. That is what lets [backfillSeasonIds]
  ///   and this method re-run as often as needed without demoting a correct
  ///   classification.
  ///
  /// [onlyIfEpoch], when given, drops the write if [deleteAll] has run since
  /// that [dataEpoch] was read — see [dataEpoch].
  Future<void> upsertAll(
    String uid,
    List<RankedMatch> matches, {
    Map<String, SeasonMeta> seasons = const {},
    int? onlyIfEpoch,
  }) async {
    // Rows are filed under the match's own uid, so a missing or different one would land under
    // another player (or '') and never show for [uid]. Skipped instead.
    final own = [
      for (final m in matches)
        if (m.uid == uid) m,
    ];
    if (own.length != matches.length) {
      log.w(
        'History sync skipped ${matches.length - own.length} of '
        '${matches.length} matches that did not carry the requested uid',
      );
    }
    if (own.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final m in own) {
      final row = m.withPlausibleStats().toStoredMap();
      final derivedSeasonId = seasons.isNotEmpty
          ? seasonIdForEndTime(m.endTime, seasons.values)
          : null;
      batch.rawInsert(_syncUpsertSql, [
        for (final column in _upsertColumns)
          column == 'season_id' ? derivedSeasonId : row[column],
      ]);
    }
    // Checked right before the commit is queued: sqflite runs operations in
    // order, so a deleteAll() after this check still clears what it wrote.
    if (onlyIfEpoch != null && onlyIfEpoch != _dataEpoch) return;
    await batch.commit(noResult: true);
  }

  /// Classifies rows with no known season: both untouched (NULL, predating the
  /// [season_id] column) and previously-unmatched ([kUnknownSeasonId]) rows are
  /// re-derived from their end timestamp against [seasons]. Re-including
  /// [kUnknownSeasonId] rows lets matches that were unmatched before their split's
  /// window was cached self-correct once that window becomes known, rather than
  /// being stuck the moment they're first labeled "Unknown". Cheap no-op once
  /// every row already matches its correct id, so it's safe to call often;
  /// skipped entirely until season metadata exists.
  Future<void> backfillSeasonIds(Map<String, SeasonMeta> seasons) async {
    if (seasons.isEmpty) return;
    final db = await _open();
    // Uses [_needsSeasonId] verbatim so SQLite can serve it from the matching
    // partial index instead of scanning every row.
    final rows = await db.query(
      table,
      columns: ['id', 'end_ms', 'season_id'],
      where: _needsSeasonId,
    );
    if (rows.isEmpty) return;
    final batch = db.batch();
    var changed = false;
    for (final r in rows) {
      final endMs = (r['end_ms'] as num?)?.toInt() ?? 0;
      final endTime = DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true);
      final newId = seasonIdForEndTime(endTime, seasons.values);
      if (newId == r['season_id']) continue;
      changed = true;
      batch.update(
        table,
        {'season_id': newId},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
    if (changed) await batch.commit(noResult: true);
  }

  /// Applies hand corrections to the match [id] and flags each changed column
  /// so later syncs leave it alone.
  ///
  /// Keys of [values] must be in [kEditableMatchFields]; anything else throws.
  /// The row's `id` is never rewritten, so correcting a field can't produce a
  /// second row for the same match. Flags accumulate across calls.
  ///
  /// Values are range-checked against the same plausibility constants
  /// [RankedMatch.withPlausibleStats] applies to synced matches. This is
  /// deliberately enforced here and not only in the edit form: an edit sets the
  /// edited flag, which stops every later sync from correcting the column, so
  /// an out-of-range value written through this method is permanent.
  ///
  /// [excluded], when given, is set in the same transaction.
  ///
  /// Returns `false` when no row matches [id]; nothing is written.
  Future<bool> editMatch(
    String id,
    Map<String, Object?> values, {
    bool? excluded,
  }) async {
    final invalid = values.keys.toSet().difference(kEditableMatchFields);
    if (invalid.isNotEmpty) {
      throw ArgumentError('Not editable: ${invalid.join(', ')}');
    }
    _assertEditableRange(values, 'kills', 0, kMaxPlausibleKills);
    _assertEditableRange(values, 'damage', 0, kMaxPlausibleDamage);
    _assertEditableRange(
      values,
      'rp_change',
      kMinPlausibleRpChange,
      kImplausibleRpThreshold - 1,
    );
    if (values.isEmpty && excluded == null) return true;
    final db = await _open();
    // One transaction so the edit and exclusion can't half-apply.
    return db.transaction((txn) async {
      final existing = await txn.query(
        table,
        columns: ['edited_fields'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isEmpty) return false;
      final flags = {
        ...decodeEditedFields(existing.first['edited_fields']),
        ...values.keys,
      };
      await txn.update(
        table,
        {
          ...values,
          if (values.isNotEmpty) 'edited_fields': encodeEditedFields(flags),
          if (excluded != null) 'excluded': excluded ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    });
  }

  /// Throws when [values] carries [key] with a value outside `[min, max]`.
  /// A null is always allowed - for kills/damage it is the legitimate "not
  /// reported" value, and the caller validates required-ness separately.
  static void _assertEditableRange(
    Map<String, Object?> values,
    String key,
    int min,
    int max,
  ) {
    if (!values.containsKey(key)) return;
    final v = values[key];
    if (v == null) return;
    if (v is! int || v < min || v > max) {
      throw ArgumentError.value(v, key, 'must be an int in [$min, $max]');
    }
  }

  /// Drops the edited flag on [field] for the match [id], or on every field
  /// when [field] is null.
  ///
  /// The pre-edit values aren't kept, so the column holds the corrected value
  /// until the next sync overwrites it with whatever upstream is serving.
  Future<void> clearEdits(String id, {String? field}) async {
    final db = await _open();
    final existing = await db.query(
      table,
      columns: ['edited_fields'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isEmpty) return;
    final flags = {...decodeEditedFields(existing.first['edited_fields'])};
    if (field == null) {
      flags.clear();
    } else {
      flags.remove(field);
    }
    await db.update(
      table,
      {'edited_fields': encodeEditedFields(flags)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Sets [RankedMatch.excluded] on the match [id]. Deliberately separate
  /// from [editMatch]: a sync never writes or clears it, and a restore can
  /// only set it (see [_conflictUpdateSet]).
  ///
  /// Returns `false` when no row matches [id], same as [editMatch].
  Future<bool> setExcluded(String id, bool excluded) async {
    final db = await _open();
    final count = await db.update(
      table,
      {'excluded': excluded ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  /// Match count per season id for [uid] (unclassified NULL rows omitted),
  /// including non-ranked games. Test-only — [rankedSeasonCounts] below is
  /// what actually drives the split picker in production; it additionally
  /// scopes to ranked games only, which this does not.
  @visibleForTesting
  Future<Map<String, int>> seasonCounts(String uid) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT season_id, COUNT(*) AS c FROM $table '
      'WHERE uid = ? AND season_id IS NOT NULL GROUP BY season_id',
      [uid],
    );
    return {
      for (final r in rows) r['season_id'] as String: (r['c'] as num).toInt(),
    };
  }

  /// Ranked-match count per split for [uid], keyed by season id with NULL folded
  /// into [kUnknownSeasonId]. Only counts *ranked* games (BR with an RP change),
  /// so a split that holds only pubs never shows in the picker. Drives the split
  /// dropdown without hydrating a single match — the core of scoping loads to
  /// one split at a time.
  Future<Map<String, int>> rankedSeasonCounts(String uid) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT COALESCE(season_id, ?) AS sid, COUNT(*) AS c FROM $table '
      "WHERE uid = ? AND game_mode = 'BATTLE_ROYALE' AND rp_change != 0 "
      'AND excluded = 0 AND $kSqlPlausibleRpChange GROUP BY sid',
      [kUnknownSeasonId, uid],
    );
    return {for (final r in rows) r['sid'] as String: (r['c'] as num).toInt()};
  }

  /// All persisted matches for [uid], newest first. Test-only: hydrating the
  /// whole history is exactly what the split-scoped architecture
  /// ([getBySeason], the SQL aggregates below) exists to avoid in production.
  @visibleForTesting
  Future<List<RankedMatch>> getAll(String uid) async {
    final db = await _open();
    final rows = await db.query(
      table,
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'start_ms DESC',
    );
    return rows.map(RankedMatch.fromStoredMap).toList();
  }

  /// Matches for a single split, newest first (pubs included — the History tab
  /// needs them; callers filter to ranked for aggregates). The [kUnknownSeasonId]
  /// bucket also picks up rows whose [season_id] is still NULL (never classified),
  /// matching how [rankedSeasonCounts] folds NULL into Unknown.
  Future<List<RankedMatch>> getBySeason(String uid, String seasonId) async {
    final db = await _open();
    final rows = seasonId == kUnknownSeasonId
        ? await db.query(
            table,
            where: 'uid = ? AND (season_id = ? OR season_id IS NULL)',
            whereArgs: [uid, kUnknownSeasonId],
            orderBy: 'start_ms DESC',
          )
        : await db.query(
            table,
            where: 'uid = ? AND season_id = ?',
            whereArgs: [uid, seasonId],
            orderBy: 'start_ms DESC',
          );
    return rows.map(RankedMatch.fromStoredMap).toList();
  }

  // ── SQL aggregation (drives the Lifetime view without hydrating matches) ────
  //
  // These compute the same figures as the Dart aggregates in `ranked_aggregates`
  // but as GROUP BY sums, so a 50k-match lifetime scope returns a handful of rows
  // instead of loading every match. Semantics mirror the Dart path exactly:
  // ranked-only (`BATTLE_ROYALE` with an RP change) and limited to matches that
  // count toward the stats — see [RankedMatch.countsTowardStats].

  /// Ranked-only WHERE scope for [uid] and an optional [seasonId] (null = every
  /// split — the lifetime scope). Folds Unknown/NULL together like [getBySeason].
  /// Leaves out hand-excluded matches and ones with an implausible RP swing
  /// ([kSqlPlausibleRpChange], the SQL form of [RankedMatch.isAutoExcluded]).
  ///
  /// [includeNonCounting] keeps those matches in; it is only for reading the
  /// running RP, which they still moved.
  (String, List<Object?>) _rankedScope(
    String uid,
    String? seasonId, {
    bool includeNonCounting = false,
  }) {
    final buf = StringBuffer(
      "uid = ? AND game_mode = 'BATTLE_ROYALE' AND rp_change != 0",
    );
    if (!includeNonCounting) {
      buf.write(' AND excluded = 0 AND $kSqlPlausibleRpChange');
    }
    final args = <Object?>[uid];
    if (seasonId == kUnknownSeasonId) {
      buf.write(' AND (season_id = ? OR season_id IS NULL)');
      args.add(kUnknownSeasonId);
    } else if (seasonId != null) {
      buf.write(' AND season_id = ?');
      args.add(seasonId);
    }
    return (buf.toString(), args);
  }

  // Shared aggregate columns. Always paired with [_rankedScope], which already
  // keeps implausible RP swings out, so net RP and win/loss need no test of
  // their own - restating the rule here is what let these columns drift from
  // the Dart aggregates in the past.
  static const _aggCols =
      '''
      COUNT(*) AS games,
      COALESCE(SUM(kills), 0) AS kills,
      COALESCE(SUM(damage), 0) AS damage,
      COUNT(kills) AS kills_games,
      COUNT(damage) AS damage_games,
      COALESCE(SUM(length_secs), 0) AS length_secs,
      COALESCE(SUM(rp_change), 0) AS net_rp,
      COALESCE(SUM(CASE WHEN rp_change > 0 THEN 1 ELSE 0 END), 0) AS wins,
      COALESCE(SUM(CASE WHEN rp_change < 0 THEN 1 ELSE 0 END), 0) AS losses''';

  /// Window summary for [uid] across [seasonId] (null = lifetime), via SQL.
  Future<RankedSummary> summaryFor(String uid, {String? seasonId}) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final agg = (await db.rawQuery(
      'SELECT $_aggCols FROM $table WHERE $where',
      args,
    )).first;
    final total = RankedAgg()..addRow(agg);
    if (total.games == 0) return RankedSummary.empty;
    // Newest ranked match supplies current RP / rank image, counting or not.
    final (latestWhere, latestArgs) = _rankedScope(
      uid,
      seasonId,
      includeNonCounting: true,
    );
    final latest = await db.rawQuery(
      'SELECT cumulative_rp, rank_img FROM $table WHERE $latestWhere '
      'ORDER BY end_ms DESC LIMIT 1',
      latestArgs,
    );
    final newest = latest.isEmpty ? null : latest.first;
    return total.toSummary(
      currentRp: (newest?['cumulative_rp'] as num?)?.toInt() ?? 0,
      latestRankImg: newest?['rank_img'] as String? ?? '',
    );
  }

  /// Ranked summary split by full vs. partial squad for [uid] across
  /// [seasonId] (null = lifetime), via the same `GROUP BY` shape as
  /// [legendBreakdownsFor]. `currentRp`/`latestRankImg` are left at
  /// [RankedSummary.empty]'s defaults — squad composition has no single
  /// "current rank" the way a legend or map split doesn't either, and neither
  /// field is used by this split's UI.
  Future<({RankedSummary full, RankedSummary partial})> squadBreakdownFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    // COALESCE'd on both sides: a NULL is_party_full (e.g. an imported row
    // missing the column) must join the partial-squad bucket, not form its
    // own group that neither `== 1` nor `== 0` below ever matches — matches
    // RankedMatch.fromStoredMap's null-to-false convention.
    final rows = await db.rawQuery(
      'SELECT COALESCE(is_party_full, 0) AS is_party_full, $_aggCols '
      'FROM $table WHERE $where '
      'GROUP BY COALESCE(is_party_full, 0)',
      args,
    );

    RankedSummary summaryFromRow(int isPartyFull) {
      final agg = RankedAgg();
      for (final r in rows) {
        if ((r['is_party_full'] as num?)?.toInt() == isPartyFull) agg.addRow(r);
      }
      return agg.toSummary();
    }

    return (full: summaryFromRow(1), partial: summaryFromRow(0));
  }

  /// Per-legend breakdown for [uid] across [seasonId] (null = lifetime), sorted
  /// by total RP descending — matching [legendBreakdowns].
  ///
  /// Grouped by the raw `legend` column first since SQL can't canonicalize a
  /// case variant on read; rows are merged in Dart after, the same shape
  /// [mapBreakdownsFor] uses for map-key variants. Without this, `bloodhound`
  /// and `Bloodhound` for the same player would render as two
  /// identically-labelled rows. Sorting moves to Dart too, since a raw row's
  /// own `net_rp` no longer reflects its merged group's total.
  Future<List<LegendBreakdown>> legendBreakdownsFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT legend, $_aggCols FROM $table WHERE $where GROUP BY legend',
      args,
    );

    final byLegend = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      final rawLegend = r['legend'] as String? ?? 'Unknown';
      byLegend.putIfAbsent(canonicalLegendName(rawLegend), () => []).add(r);
    }

    return [
      for (final entry in byLegend.entries)
        (RankedAgg()..addAllRows(entry.value)).toLegend(entry.key),
    ]..sort(byTotalRpThenName);
  }

  /// Per-map breakdown for [uid] across [seasonId] (null = lifetime), sorted by
  /// games descending — matching [mapBreakdowns].
  ///
  /// Grouped by the raw `map_key` first since SQL can't canonicalize
  /// map-key variants; rows are merged in Dart by [canonicalMapKey] after,
  /// the same shape [legendMapBreakdownsFor] uses. Without this, `edistrict`
  /// and `edistrict_rotation` rows for the same player would render as two
  /// identically-labelled "E-District" entries.
  Future<List<MapBreakdown>> mapBreakdownsFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT map_key, $_aggCols FROM $table WHERE $where '
      'GROUP BY map_key',
      args,
    );

    final byMap = <String, List<Map<String, Object?>>>{};
    final representativeKey = <String, String>{};
    for (final r in rows) {
      final rawKey = r['map_key'] as String? ?? 'UNKNOWN';
      final canonical = canonicalMapKey(rawKey);
      byMap.putIfAbsent(canonical, () => []).add(r);
      representativeKey.putIfAbsent(canonical, () => rawKey);
    }

    return [
      for (final entry in byMap.entries)
        (RankedAgg()..addAllRows(entry.value)).toMap(
          representativeKey[entry.key]!,
          battleRoyaleMapName(representativeKey[entry.key]!),
        ),
    ]..sort(byGamesThenName);
  }

  /// Per (legend, map) breakdown for [uid] across [seasonId] (null =
  /// lifetime), via SQL — the counterpart to [legendMapBreakdowns] for a split
  /// that isn't necessarily the one currently loaded in memory (e.g. the
  /// split-comparison tab). Grouped by the raw columns first since SQL can't
  /// canonicalize map-key variants; rows are merged in Dart after applying the
  /// same constants-only inclusion rule [legendMapBreakdowns] uses.
  Future<List<LegendMapCell>> legendMapBreakdownsFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT legend, map_key, $_aggCols FROM $table WHERE $where '
      'GROUP BY legend, map_key',
      args,
    );

    final byPair = <(String, String), List<Map<String, Object?>>>{};
    for (final r in rows) {
      final legend =
          kLegendsByName[(r['legend'] as String? ?? '').toLowerCase()]?.name;
      final mapName = battleRoyaleMapInfo(r['map_key'] as String? ?? '')?.name;
      if (legend == null || mapName == null) continue;
      byPair.putIfAbsent((legend, mapName), () => []).add(r);
    }

    return [
      for (final entry in byPair.entries)
        (RankedAgg()..addAllRows(entry.value)).toCell(
          entry.key.$1,
          entry.key.$2,
        ),
    ];
  }

  /// Time-of-day and day-of-week performance for [uid] across [seasonId]
  /// (null = lifetime), from one narrow (start time, RP) projection fed to the
  /// `*BucketsFromRankedRows` helpers, so no [RankedMatch] is hydrated.
  Future<({List<HourBucket> hours, List<WeekdayBucket> weekdays})>
  timeBucketsFor(String uid, {String? seasonId}) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT start_ms, rp_change FROM $table WHERE $where',
      args,
    );
    final pairs = [
      for (final r in rows)
        (
          (r['start_ms'] as num?)?.toInt() ?? 0,
          (r['rp_change'] as num?)?.toInt() ?? 0,
        ),
    ];
    return (
      hours: timeOfDayBucketsFromRankedRows(pairs),
      weekdays: dayOfWeekBucketsFromRankedRows(pairs),
    );
  }

  /// Ranked matches for one legend across [seasonId] (null = lifetime), newest
  /// first — the lazy drill-down query the Lifetime Legends tab uses on tap
  /// instead of filtering a whole in-memory history.
  ///
  /// Matches case-insensitively: [legendBreakdownsFor] already merges every
  /// raw casing of [legend] (e.g. `edistrict`-style variants, but for
  /// legends — `bloodhound`/`Bloodhound`) into one canonically-named row, so
  /// the drill-down from that row must return every match behind it, not
  /// just the ones under whichever raw casing happened to be more common.
  ///
  /// Folds a NULL `legend` into `'Unknown'` first, matching
  /// [legendBreakdownsFor]'s grouping — plain equality never matches NULL,
  /// so the "Unknown" row would otherwise drill down to too few matches.
  Future<List<RankedMatch>> matchesForLegend(
    String uid,
    String legend, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      "SELECT * FROM $table WHERE $where AND "
      "LOWER(COALESCE(legend, 'Unknown')) = LOWER(?) "
      'ORDER BY start_ms DESC',
      [...args, legend],
    );
    return rows.map(RankedMatch.fromStoredMap).toList();
  }

  /// Ranked matches for one map across [seasonId] (null = lifetime), newest
  /// first — the lazy drill-down query the Lifetime Maps tab uses on tap.
  ///
  /// Matches every raw spelling [battleRoyaleMapKeyVariants] considers the same map
  /// as [mapKey] (e.g. `edistrict` and `edistrict_rotation`), not just the
  /// exact string — [mapBreakdownsFor] already merges those into one row, so the
  /// drill-down from that row must return every match behind it, not just
  /// the ones under whichever raw key happened to be its representative.
  ///
  /// Matches case-insensitively, and folds a NULL `map_key` into `'UNKNOWN'`
  /// first — the same two normalizations [mapBreakdownsFor] applies when
  /// building the group this drill-down opens from. Without both, an
  /// unrecognised map or differently-cased key returned fewer matches than
  /// the row it was opened from counted, since a plain `IN (...)` is
  /// exact-string and never matches NULL.
  Future<List<RankedMatch>> matchesForMap(
    String uid,
    String mapKey, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final variants = battleRoyaleMapKeyVariants(mapKey);
    final placeholders = List.filled(variants.length, 'LOWER(?)').join(', ');
    final rows = await db.rawQuery(
      "SELECT * FROM $table WHERE $where AND "
      "LOWER(COALESCE(map_key, 'UNKNOWN')) IN ($placeholders) "
      'ORDER BY start_ms DESC',
      [...args, ...variants],
    );
    return rows.map(RankedMatch.fromStoredMap).toList();
  }

  /// The single best RP/kills/damage game for [uid] across [seasonId] (null =
  /// lifetime) — one `ORDER BY ... LIMIT 1` query per stat rather than
  /// hydrating the whole history, so this stays cheap at Lifetime scope. Only
  /// matches that count toward the stats are considered; a null kills/damage
  /// game means no row in scope ever reported that tracker.
  ///
  /// Ties go to the most recently ended match (`end_ms DESC`), the same rule
  /// [personalRecords] applies — equal kill counts are common, and without
  /// an explicit tie-break SQLite may pick any of the tied rows.
  Future<PersonalBestGames> personalBestGamesFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);

    Future<RankedMatch?> top(String column, {String? extraWhere}) async {
      final rows = await db.rawQuery(
        'SELECT * FROM $table WHERE $where${extraWhere ?? ''} '
        'ORDER BY $column DESC, end_ms DESC LIMIT 1',
        args,
      );
      return rows.isEmpty ? null : RankedMatch.fromStoredMap(rows.first);
    }

    return (
      bestRpGame: await top('rp_change'),
      // `IS NOT NULL` is load-bearing: `LIMIT 1` on a non-empty table always
      // returns a row, so without it an untracked stat returned a real match
      // with a null value instead of no match at all.
      bestKillsGame: await top('kills', extraWhere: ' AND kills IS NOT NULL'),
      bestDamageGame: await top(
        'damage',
        extraWhere: ' AND damage IS NOT NULL',
      ),
    );
  }

  Future<int> count(String uid) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE uid = ?',
      [uid],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Every stored match id, across all UIDs. Backs the backup-import preview,
  /// which needs to say how many of a backup file's rows are actually new
  /// before the user commits to restoring it — a plain `id`-only projection
  /// avoids hydrating any [RankedMatch].
  Future<Set<String>> allIds() async {
    final db = await _open();
    final rows = await db.query(table, columns: ['id']);
    return {for (final r in rows) r['id'] as String};
  }

  // ── RP snapshots ───────────────────────────────────────────────────────────

  /// [uid]'s RP snapshots, oldest first - the order every consumer assumes
  /// (`lastResetIndex` walks backwards, `weekDelta` takes `before.last`).
  Future<List<StatSnapshot>> snapshotsFor(String uid) async {
    final db = await _open();
    final rows = await db.query(
      snapshotTable,
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'ts_ms ASC',
    );
    return [
      for (final r in rows)
        StatSnapshot(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (r['ts_ms'] as num).toInt(),
          ),
          rp: (r['rp'] as num).toInt(),
          seasonId: r['season_id'] as String?,
        ),
    ];
  }

  /// Appends one reading for [uid]. O(1) - the whole point of the table.
  /// Replaces on conflict so a repeated write at the same instant can't
  /// duplicate the row.
  ///
  /// [onlyIfEpoch] — see [upsertAll].
  Future<void> appendSnapshotFor(
    String uid,
    StatSnapshot snapshot, {
    int? onlyIfEpoch,
  }) async {
    final db = await _open();
    if (onlyIfEpoch != null && onlyIfEpoch != _dataEpoch) return;
    await db.insert(snapshotTable, {
      'uid': uid,
      'ts_ms': snapshot.timestamp.millisecondsSinceEpoch,
      'rp': snapshot.rp,
      'season_id': snapshot.seasonId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Bulk insert, for draining the legacy prefs blob. Idempotent via the
  /// primary key, so an interrupted migration can simply be re-run.
  Future<void> appendSnapshotsFor(
    String uid,
    List<StatSnapshot> snapshots,
  ) async {
    if (snapshots.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final s in snapshots) {
      batch.insert(snapshotTable, {
        'uid': uid,
        'ts_ms': s.timestamp.millisecondsSinceEpoch,
        'rp': s.rp,
        'season_id': s.seasonId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Trims RP snapshots, returning how many rows went. Never trimmed: [profileUids], any UID
  /// with stored match history (e.g. a removed profile) and the legacy UID-less bucket.
  /// [favoriteUids] keep [favoriteSnapshotMaxAge]; everyone else [otherSnapshotMaxAge].
  Future<int> pruneSnapshots({
    required Set<String> profileUids,
    required Set<String> favoriteUids,
    DateTime? now,
  }) async {
    final db = await _open();
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    String marks(Set<String> s) => List.filled(s.length, '?').join(', ');
    return db.rawDelete(
      '''
      DELETE FROM $snapshotTable
      WHERE uid != ''
        AND uid NOT IN (${marks(profileUids)})
        AND NOT EXISTS (SELECT 1 FROM $table m WHERE m.uid = $snapshotTable.uid)
        AND ts_ms < CASE WHEN uid IN (${marks(favoriteUids)}) THEN ? ELSE ? END
      ''',
      [
        ...profileUids,
        ...favoriteUids,
        nowMs - favoriteSnapshotMaxAge.inMilliseconds,
        nowMs - otherSnapshotMaxAge.inMilliseconds,
      ],
    );
  }

  /// Snapshot rows stored for [uid]. Test-only — production reads go through
  /// [snapshotsFor], which the RP graph needs the rows from anyway.
  @visibleForTesting
  Future<int> snapshotCount(String uid) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $snapshotTable WHERE uid = ?',
      [uid],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Every snapshot row across all UIDs - the export counterpart of
  /// [exportRows].
  Future<List<Map<String, Object?>>> exportSnapshotRows() async {
    final db = await _open();
    return db.query(snapshotTable, orderBy: 'uid ASC, ts_ms ASC');
  }

  /// Restores snapshot rows from an export. Idempotent. Returns how many
  /// rows were skipped as unusable.
  ///
  /// [executor] lets [importBackupData] run this against a [Transaction]
  /// instead of opening its own connection, so it can commit atomically
  /// alongside [importRows]. Defaults to the store's own database for
  /// standalone callers.
  Future<int> importSnapshotRows(
    List<dynamic> rows, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _open();
    final batch = db.batch();
    var skipped = 0;
    for (final r in rows) {
      final uid = r is Map ? r['uid'] : null;
      final tsMs = r is Map ? r['ts_ms'] : null;
      final rp = r is Map ? r['rp'] : null;
      final seasonId = r is Map ? r['season_id'] : null;
      // uid/ts_ms are NOT NULL primary-key columns, and a wrong type can't be
      // bound at all — any of these would fail the whole batch.
      if (uid is! String ||
          tsMs is! num ||
          (rp != null && rp is! num) ||
          (seasonId != null && seasonId is! String)) {
        skipped++;
        continue;
      }
      batch.insert(snapshotTable, {
        'uid': uid,
        'ts_ms': tsMs.toInt(),
        'rp': (rp as num?)?.toInt() ?? 0,
        'season_id': seasonId as String?,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    return skipped;
  }

  // ── Export / import ────────────────────────────────────────────────────────

  /// Every row across all UIDs — used to build the single-file export.
  Future<List<Map<String, Object?>>> exportRows() async {
    final db = await _open();
    return db.query(table, orderBy: 'start_ms DESC');
  }

  /// Every row, [pageSize] at a time, paged by primary key (not `OFFSET`) so a concurrent sync
  /// can't shift rows past the cursor. Lets the export avoid holding the whole history.
  Stream<List<Map<String, Object?>>> exportRowPages({
    int pageSize = 250,
  }) async* {
    final db = await _open();
    String? lastId;
    while (true) {
      final page = await db.query(
        table,
        where: lastId == null ? null : 'id > ?',
        whereArgs: lastId == null ? null : [lastId],
        orderBy: 'id',
        limit: pageSize,
      );
      if (page.isEmpty) return;
      yield page;
      if (page.length < pageSize) return;
      lastId = page.last['id'] as String;
    }
  }

  /// Columns [importRows] will accept from a backup file. Anything else in the
  /// JSON is dropped rather than passed to SQLite as a column name.
  static const _importableColumns = {
    'id',
    'uid',
    'player_name',
    'legend',
    'game_mode',
    'map_key',
    'rp_change',
    'cumulative_rp',
    'rank_img',
    'length_secs',
    'start_ms',
    'end_ms',
    'is_party_full',
    'trackers',
    'season_id',
    'kills',
    'damage',
    'edited_fields',
    'excluded',
  };

  /// Columns holding integers; the rest of [_importableColumns] hold text.
  static const _integerColumns = {
    'rp_change',
    'cumulative_rp',
    'length_secs',
    'start_ms',
    'end_ms',
    'is_party_full',
    'kills',
    'damage',
    'excluded',
  };

  /// Restores rows from an export (single JSON file). Idempotent. Returns
  /// how many rows were skipped as unusable.
  ///
  /// The file comes from the user, so a bad row is skipped and counted
  /// rather than failing the whole batch. A row with an implausible `cumulative_rp` or
  /// untrusted `rank_img` is imported without that value (count logged). A row is skipped unless: it's
  /// filtered to [_importableColumns] (an unknown key would reach SQLite as
  /// a column name); it has a non-empty `id` and `uid`, and numeric
  /// `start_ms`/`end_ms`; and every value is bindable (null, number, or
  /// string — a JSON boolean is coerced to 1/0).
  ///
  /// A conflicting id goes through [_conflictUpdateSet]'s restore form: like
  /// [upsertAll]'s edit-aware, season-upgrade-only rule, except a value the
  /// backup lacks keeps the stored one instead of going back to NULL (the
  /// bug with the old plain `INSERT OR REPLACE`, and later with reusing the
  /// sync form here). For the same reason, a row with no `kills`/`damage`
  /// key at all has them derived from its `trackers` blob, as a sync would.
  ///
  /// Unlike a sync, a restore also carries its own edit flags, merged into
  /// the stored row's rather than dropped — otherwise restoring a backup onto
  /// a device that already synced the same matches (the usual phone
  /// migration) applied the correction but not its flag, and the next sync
  /// silently reverted it. A column flagged only by the backup takes the
  /// backup's value; one flagged by both keeps the local value.
  ///
  /// [executor] — see [importSnapshotRows]'s doc for why this exists.
  Future<int> importRows(
    List<dynamic> rows, {
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) return _importRowsOn(executor, rows);
    // Chunked commits need their own transaction to stay all-or-nothing.
    final db = await _open();
    return db.transaction((txn) => _importRowsOn(txn, rows));
  }

  Future<int> _importRowsOn(DatabaseExecutor db, List<dynamic> rows) async {
    // Flags already on this device, keyed by id — a small set regardless of
    // history size. Updated as rows are queued, so a backup listing the same
    // id twice still keeps both rows' flags.
    final flagsById = <String, Set<String>>{
      for (final r in await db.query(
        table,
        columns: ['id', 'edited_fields'],
        where: 'edited_fields IS NOT NULL',
      ))
        r['id'] as String: decodeEditedFields(r['edited_fields']),
    };
    var batch = db.batch();
    var queued = 0;
    var skipped = 0;
    var corrected = 0;
    for (final r in rows) {
      final row = r is Map
          ? _importableRow(r, onCorrected: () => corrected++)
          : null;
      if (row == null) {
        skipped++;
        continue;
      }
      final id = row['id'] as String;
      final flags = {
        ...?flagsById[id],
        ...decodeEditedFields(row['edited_fields']),
      };
      flagsById[id] = flags;
      row['edited_fields'] = encodeEditedFields(flags);
      batch.rawInsert(_restoreUpsertSql, [
        for (final column in _restoreColumns) row[column],
      ]);
      if (++queued >= _importBatchSize) {
        await batch.commit(noResult: true);
        batch = db.batch();
        queued = 0;
      }
    }
    if (queued > 0) await batch.commit(noResult: true);
    if (corrected > 0) {
      log.w('Backup import: $corrected implausible values were left out');
    }
    return skipped;
  }

  /// [r] as a row [importRows] can queue, or null when it isn't usable —
  /// see [importRows] for the rules.
  ///
  /// [onCorrected] is called per value dropped as implausible; the row is still imported.
  static Map<String, Object?>? _importableRow(
    Map<dynamic, dynamic> r, {
    void Function()? onCorrected,
  }) {
    final id = r['id'];
    final uid = r['uid'];
    if (id is! String || id.isEmpty) return null;
    if (uid is! String || uid.isEmpty) return null;
    if (r['start_ms'] is! num || r['end_ms'] is! num) return null;

    // Type-check every column: SQLite would store text in an INTEGER column
    // and break the views that later load the row.
    final row = <String, Object?>{};
    for (final col in _importableColumns) {
      final v = r[col];
      if (_integerColumns.contains(col)) {
        if (v == null || v is num) {
          row[col] = (v as num?)?.toInt();
        } else if (v is bool) {
          row[col] = v ? 1 : 0;
        } else {
          return null;
        }
      } else if (v == null || v is String) {
        row[col] = v;
      } else {
        return null;
      }
    }
    // NOT NULL in the table; absent means "not excluded".
    row['excluded'] = (row['excluded'] as int? ?? 0) != 0 ? 1 : 0;

    // The stored GLOB is looser than [SeasonMeta.isSplitId] and never demotes
    // an id, so drop anything Dart wouldn't accept.
    final seasonId = row['season_id'];
    if (seasonId is! String || !SeasonMeta.isSplitId(seasonId)) {
      row['season_id'] = null;
    }

    // Running RP feeds "current RP" and the badge is fetched, so neither is trusted. A dropped
    // value restores as missing (the stored one is kept), not 0.
    final cumulativeRp = row['cumulative_rp'] as int?;
    if (cumulativeRp != null &&
        (cumulativeRp < 0 || cumulativeRp > kMaxPlausibleCumulativeRp)) {
      row['cumulative_rp'] = null;
      onCorrected?.call();
    }
    final rankImg = row['rank_img'] as String?;
    if (rankImg != null &&
        rankImg.isNotEmpty &&
        !isTrustedRankImageUrl(rankImg)) {
      row['rank_img'] = null;
      onCorrected?.call();
    }

    // The same range check a sync and a hand edit apply.
    int? plausible(Object? v, int max) =>
        v is int && v >= 0 && v <= max ? v : null;
    row['kills'] = plausible(row['kills'], kMaxPlausibleKills);
    row['damage'] = plausible(row['damage'], kMaxPlausibleDamage);

    final missingKills = !r.containsKey('kills');
    final missingDamage = !r.containsKey('damage');
    if (missingKills || missingDamage) {
      final trackers = RankedMatch.fromStoredMap({
        'trackers': row['trackers'],
      }).trackers;
      if (missingKills) {
        row['kills'] = plausible(
          RankedMatch.killsFrom(trackers),
          kMaxPlausibleKills,
        );
      }
      if (missingDamage) {
        row['damage'] = plausible(
          RankedMatch.damageFrom(trackers),
          kMaxPlausibleDamage,
        );
      }
    }
    return row;
  }

  /// Restores ranked-match rows and RP-snapshot rows from a backup together,
  /// inside one sqflite transaction — both commit or neither does, so a
  /// mid-restore failure can't leave one table updated and the other not.
  /// Prefer this over calling [importRows] / [importSnapshotRows] separately
  /// whenever a backup carries both, which is every version since v3.
  ///
  /// [restorePrefs], when given, runs last, still inside this transaction —
  /// if it throws, sqflite rolls back the row imports too. That's what makes
  /// `commitBackupImport`'s combined restore atomic despite
  /// `SharedPreferences` having no transaction primitive of its own.
  ///
  /// Returns how many rows, across both tables, were skipped as unusable.
  Future<int> importBackupData({
    required List<dynamic> matchRows,
    required List<dynamic> snapshotRows,
    Future<void> Function()? restorePrefs,
  }) async {
    final db = await _open();
    return db.transaction((txn) async {
      final skipped =
          await importRows(matchRows, executor: txn) +
          await importSnapshotRows(snapshotRows, executor: txn);
      if (restorePrefs != null) await restorePrefs();
      return skipped;
    });
  }

  /// Bumped by [deleteAll]. A writer in flight when the user clears
  /// everything (a `/games` sync, an RP snapshot) reads this beforehand and
  /// passes it back as `onlyIfEpoch`, so its write drops instead of
  /// resurrecting deleted data.
  int get dataEpoch => _dataEpoch;
  int _dataEpoch = 0;

  /// Drops both tables. Backs "Clear all data", which promises *everything* -
  /// RP snapshots included, since they are the app's other record of the
  /// player's history.
  Future<void> deleteAll() async {
    // Bumped before the first await, so a writer that checks after this
    // point already sees the clear.
    _dataEpoch++;
    final db = await _open();
    await db.delete(table);
    await db.delete(snapshotTable);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
