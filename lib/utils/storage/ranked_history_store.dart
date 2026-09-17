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

  static const _version = 8;

  // Scope of the lazy season backfill — the rows it still has work to do on.
  // Used verbatim by both a partial index and the backfill query, which must
  // stay byte-identical or SQLite won't apply the index and the backfill falls
  // back to a full-table scan. One constant, so the two can't drift.
  static const _needsSeasonId =
      "season_id IS NULL OR season_id = '$kUnknownSeasonId'";

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
            edited_fields TEXT
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
        // RankedMatch.isRankedOutlier already excludes an implausible swing
        // from every RP aggregate, computed fresh from the stored value with
        // no migration needed.
        if (oldVersion < 7) {
          await _repairImplausibleStats(db);
        }
        // v7 → v8: RP snapshots move out of an ever-growing SharedPreferences
        // JSON string into a real table. Prefs migration happens separately
        // via `migrateSnapshotsFromPrefs`, which needs SharedPreferences.
        if (oldVersion < 8) {
          await _createSnapshotTable(db);
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

  /// `col = CASE WHEN <col is flagged edited> THEN col ELSE excluded.col END`
  /// for every user-editable column. The comma-delimited `edited_fields` form
  /// lets membership be a plain `instr` test.
  static String get _editAwareAssignments => [
    for (final f in kEditableMatchFields)
      "$f = CASE WHEN instr(COALESCE(edited_fields, ''), ',$f,') > 0 "
          'THEN $f ELSE excluded.$f END',
  ].join(',\n          ');

  /// Shared `ON CONFLICT(id) DO UPDATE SET` body for [upsertAll] (a sync) and
  /// [importRows] (a backup restore) — both must resolve a conflicting id the
  /// same way, or a hand correction could survive one path and be silently
  /// reverted by the other. Derived once so they can't drift, the same
  /// reasoning [_editAwareAssignments]/[_needsSeasonId] already follow here.
  static String get _conflictUpdateSet =>
      '''
          uid = excluded.uid,
          player_name = excluded.player_name,
          game_mode = excluded.game_mode,
          cumulative_rp = excluded.cumulative_rp,
          rank_img = excluded.rank_img,
          start_ms = excluded.start_ms,
          end_ms = excluded.end_ms,
          is_party_full = excluded.is_party_full,
          trackers = excluded.trackers,
          $_editAwareAssignments,
          season_id = CASE
            WHEN excluded.season_id IS NOT NULL
                 AND excluded.season_id != '$kUnknownSeasonId'
                 AND (season_id IS NULL OR season_id = '$kUnknownSeasonId')
            THEN excluded.season_id
            ELSE season_id
          END
      ''';

  /// Inserts/updates [matches] for [uid]. Idempotent via the primary key.
  ///
  /// Three groups of columns behave differently on conflict:
  ///
  /// - Most are overwritten unconditionally from the incoming row.
  /// - [kEditableMatchFields] keep a hand-corrected value and are otherwise
  ///   overwritten. `edited_fields` itself is omitted from the SET clause, so a
  ///   sync can never clear the flags that protect them.
  /// - [season_id] only ever *upgrades* — a NULL or [kUnknownSeasonId] row
  ///   adopts the freshly-derived id when [seasons] yields a real one, but a row
  ///   already carrying a real season id is never touched again, even if this
  ///   call's [seasons] is empty or incomplete. That is what lets
  ///   [backfillSeasonIds] and this method re-run as often as needed without
  ///   demoting a correct classification back to unknown.
  Future<void> upsertAll(
    String uid,
    List<RankedMatch> matches, {
    Map<String, SeasonMeta> seasons = const {},
  }) async {
    if (matches.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final m in matches) {
      final row = m.withPlausibleStats().toStoredMap();
      final derivedSeasonId = seasons.isNotEmpty
          ? seasonIdForEndTime(m.endTime, seasons.values)
          : null;
      batch.rawInsert(
        '''
        INSERT INTO $table (
          id, uid, player_name, legend, game_mode, map_key, rp_change,
          cumulative_rp, rank_img, length_secs, start_ms, end_ms,
          is_party_full, trackers, season_id, kills, damage, edited_fields
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
        $_conflictUpdateSet
        ''',
        [
          row['id'],
          row['uid'],
          row['player_name'],
          row['legend'],
          row['game_mode'],
          row['map_key'],
          row['rp_change'],
          row['cumulative_rp'],
          row['rank_img'],
          row['length_secs'],
          row['start_ms'],
          row['end_ms'],
          row['is_party_full'],
          row['trackers'],
          derivedSeasonId,
          row['kills'],
          row['damage'],
          row['edited_fields'],
        ],
      );
    }
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
  /// Returns `false` when no row matches [id] — a possible mismatch between
  /// an in-memory match's `dedupKey` and what's actually stored (e.g. a
  /// hand-edited or foreign backup imported with an `id` inconsistent with
  /// its own `uid`/`start_ms`). The caller must not report success in that
  /// case, since nothing was persisted.
  Future<bool> editMatch(String id, Map<String, Object?> values) async {
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
      kRankedOutlierThreshold - 1,
    );
    if (values.isEmpty) return true;
    final db = await _open();
    final existing = await db.query(
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
    await db.update(
      table,
      {...values, 'edited_fields': encodeEditedFields(flags)},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
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

  /// Match count per season id for [uid] (unclassified NULL rows omitted). The
  /// cheap enumeration that will drive the season picker — no row hydration.
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
      'GROUP BY sid',
      [kUnknownSeasonId, uid],
    );
    return {for (final r in rows) r['sid'] as String: (r['c'] as num).toInt()};
  }

  /// All persisted matches for [uid], newest first.
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
  // ranked-only (`BATTLE_ROYALE` with an RP change), net RP and win/loss use the
  // same outlier neutralisation ([kRankedOutlierThreshold]).

  /// Ranked-only WHERE scope for [uid] and an optional [seasonId] (null = every
  /// split — the lifetime scope). Folds Unknown/NULL together like [getBySeason].
  (String, List<Object?>) _rankedScope(String uid, String? seasonId) {
    final buf = StringBuffer(
      "uid = ? AND game_mode = 'BATTLE_ROYALE' AND rp_change != 0",
    );
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

  // Shared aggregate columns. Uses [kSqlPlausibleRpChange] rather than a
  // hand-copied threshold test - restating the rule here is what let these
  // columns drift from `RankedMatch.effectiveRpChange` in the past.
  static const _aggCols =
      '''
      COUNT(*) AS games,
      COALESCE(SUM(kills), 0) AS kills,
      COALESCE(SUM(damage), 0) AS damage,
      COUNT(kills) AS kills_games,
      COUNT(damage) AS damage_games,
      COALESCE(SUM(length_secs), 0) AS length_secs,
      COALESCE(SUM(CASE WHEN $kSqlPlausibleRpChange
                        THEN rp_change ELSE 0 END), 0) AS net_rp,
      COALESCE(SUM(CASE WHEN rp_change > 0 AND $kSqlPlausibleRpChange
                        THEN 1 ELSE 0 END), 0) AS wins,
      COALESCE(SUM(CASE WHEN rp_change < 0 AND $kSqlPlausibleRpChange
                        THEN 1 ELSE 0 END), 0) AS losses''';

  /// Window summary for [uid] across [seasonId] (null = lifetime), via SQL.
  Future<RankedSummary> summaryFor(String uid, {String? seasonId}) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final agg = (await db.rawQuery(
      'SELECT $_aggCols FROM $table WHERE $where',
      args,
    )).first;
    final games = (agg['games'] as num).toInt();
    if (games == 0) return RankedSummary.empty;
    // Newest ranked match supplies current RP / rank image.
    final latest = await db.rawQuery(
      'SELECT cumulative_rp, rank_img FROM $table WHERE $where '
      'ORDER BY end_ms DESC LIMIT 1',
      args,
    );
    final newest = latest.isEmpty ? null : latest.first;
    return RankedSummary(
      games: games,
      netRp: (agg['net_rp'] as num).toInt(),
      currentRp: (newest?['cumulative_rp'] as num?)?.toInt() ?? 0,
      latestRankImg: newest?['rank_img'] as String? ?? '',
      totalKills: (agg['kills'] as num).toInt(),
      totalDamage: (agg['damage'] as num).toInt(),
      killsGames: (agg['kills_games'] as num).toInt(),
      damageGames: (agg['damage_games'] as num).toInt(),
      totalLengthSecs: (agg['length_secs'] as num).toInt(),
      wins: (agg['wins'] as num).toInt(),
      losses: (agg['losses'] as num).toInt(),
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
    final rows = await db.rawQuery(
      'SELECT is_party_full, $_aggCols FROM $table WHERE $where '
      'GROUP BY is_party_full',
      args,
    );

    RankedSummary summaryFromRow(int isPartyFull) {
      Map<String, Object?>? agg;
      for (final r in rows) {
        if ((r['is_party_full'] as num?)?.toInt() == isPartyFull) {
          agg = r;
          break;
        }
      }
      if (agg == null) return RankedSummary.empty;
      final games = (agg['games'] as num).toInt();
      if (games == 0) return RankedSummary.empty;
      return RankedSummary(
        games: games,
        netRp: (agg['net_rp'] as num).toInt(),
        currentRp: 0,
        latestRankImg: '',
        totalKills: (agg['kills'] as num).toInt(),
        totalDamage: (agg['damage'] as num).toInt(),
        killsGames: (agg['kills_games'] as num).toInt(),
        damageGames: (agg['damage_games'] as num).toInt(),
        totalLengthSecs: (agg['length_secs'] as num).toInt(),
        wins: (agg['wins'] as num).toInt(),
        losses: (agg['losses'] as num).toInt(),
      );
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
        LegendBreakdown(
          legend: entry.key,
          games: entry.value.fold(0, (s, r) => s + (r['games'] as num).toInt()),
          totalRp: entry.value.fold(
            0,
            (s, r) => s + (r['net_rp'] as num).toInt(),
          ),
          totalKills: entry.value.fold(
            0,
            (s, r) => s + (r['kills'] as num).toInt(),
          ),
          totalDamage: entry.value.fold(
            0,
            (s, r) => s + (r['damage'] as num).toInt(),
          ),
          killsGames: entry.value.fold(
            0,
            (s, r) => s + (r['kills_games'] as num).toInt(),
          ),
          damageGames: entry.value.fold(
            0,
            (s, r) => s + (r['damage_games'] as num).toInt(),
          ),
          totalLengthSecs: entry.value.fold(
            0,
            (s, r) => s + (r['length_secs'] as num).toInt(),
          ),
          wins: entry.value.fold(0, (s, r) => s + (r['wins'] as num).toInt()),
          losses: entry.value.fold(
            0,
            (s, r) => s + (r['losses'] as num).toInt(),
          ),
        ),
    ]..sort((a, b) => b.totalRp.compareTo(a.totalRp));
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

    final out = [
      for (final entry in byMap.entries)
        MapBreakdown(
          mapKey: representativeKey[entry.key]!,
          displayName: battleRoyaleMapName(representativeKey[entry.key]!),
          games: entry.value.fold(0, (s, r) => s + (r['games'] as num).toInt()),
          totalRp: entry.value.fold(
            0,
            (s, r) => s + (r['net_rp'] as num).toInt(),
          ),
          totalKills: entry.value.fold(
            0,
            (s, r) => s + (r['kills'] as num).toInt(),
          ),
          totalDamage: entry.value.fold(
            0,
            (s, r) => s + (r['damage'] as num).toInt(),
          ),
          killsGames: entry.value.fold(
            0,
            (s, r) => s + (r['kills_games'] as num).toInt(),
          ),
          damageGames: entry.value.fold(
            0,
            (s, r) => s + (r['damage_games'] as num).toInt(),
          ),
          totalLengthSecs: entry.value.fold(
            0,
            (s, r) => s + (r['length_secs'] as num).toInt(),
          ),
          wins: entry.value.fold(0, (s, r) => s + (r['wins'] as num).toInt()),
          losses: entry.value.fold(
            0,
            (s, r) => s + (r['losses'] as num).toInt(),
          ),
        ),
    ]..sort((a, b) => b.games.compareTo(a.games));
    return out;
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
        LegendMapCell(
          legend: entry.key.$1,
          mapName: entry.key.$2,
          games: entry.value.fold(0, (s, r) => s + (r['games'] as num).toInt()),
          totalRp: entry.value.fold(
            0,
            (s, r) => s + (r['net_rp'] as num).toInt(),
          ),
          wins: entry.value.fold(0, (s, r) => s + (r['wins'] as num).toInt()),
          losses: entry.value.fold(
            0,
            (s, r) => s + (r['losses'] as num).toInt(),
          ),
        ),
    ];
  }

  /// Time-of-day performance for [uid] across [seasonId] (null = lifetime).
  /// Unlike the RP progression chart or rank-progress header, "which hour do I
  /// play best" isn't season-relative — it only needs each match's start time
  /// and RP change, so it's a good Lifetime candidate. Kept scalable with a
  /// narrow projection (2 columns, no trackers/legend/map strings — the
  /// expensive part of a full row) fed straight into
  /// [timeOfDayBucketsFromRankedRows], so no [RankedMatch] is hydrated and the
  /// bucketing logic isn't duplicated in SQL.
  Future<List<HourBucket>> timeOfDayBucketsFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT start_ms, rp_change FROM $table WHERE $where',
      args,
    );
    // Bucket straight from the two projected columns — no RankedMatch per row.
    return timeOfDayBucketsFromRankedRows([
      for (final r in rows)
        (
          (r['start_ms'] as num?)?.toInt() ?? 0,
          (r['rp_change'] as num?)?.toInt() ?? 0,
        ),
    ]);
  }

  /// Day-of-week performance for [uid] across [seasonId] (null = lifetime).
  /// Same shape and same reasoning as [timeOfDayBucketsFor] — "which day do I
  /// play best" isn't season-relative either, and the same narrow start/RP
  /// projection feeds [dayOfWeekBucketsFromRankedRows] without hydrating a
  /// [RankedMatch] per row.
  Future<List<WeekdayBucket>> dayOfWeekBucketsFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT start_ms, rp_change FROM $table WHERE $where',
      args,
    );
    return dayOfWeekBucketsFromRankedRows([
      for (final r in rows)
        (
          (r['start_ms'] as num?)?.toInt() ?? 0,
          (r['rp_change'] as num?)?.toInt() ?? 0,
        ),
    ]);
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
  Future<List<RankedMatch>> matchesForLegend(
    String uid,
    String legend, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT * FROM $table WHERE $where AND LOWER(legend) = LOWER(?) '
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
  Future<List<RankedMatch>> matchesForMap(
    String uid,
    String mapKey, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final variants = battleRoyaleMapKeyVariants(mapKey);
    final placeholders = List.filled(variants.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT * FROM $table WHERE $where AND map_key IN ($placeholders) '
      'ORDER BY start_ms DESC',
      [...args, ...variants],
    );
    return rows.map(RankedMatch.fromStoredMap).toList();
  }

  /// The single best RP/kills/damage game for [uid] across [seasonId] (null =
  /// lifetime) — one `ORDER BY ... LIMIT 1` query per stat rather than
  /// hydrating the whole history, so this stays cheap at Lifetime scope. RP
  /// excludes reset outliers, matching [RankedMatch.effectiveRpChange]; a
  /// null kills/damage game means no row in scope ever reported that tracker.
  Future<PersonalBestGames> personalBestGamesFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);

    Future<RankedMatch?> top(String column, {String? extraWhere}) async {
      final rows = await db.rawQuery(
        'SELECT * FROM $table WHERE $where${extraWhere ?? ''} '
        'ORDER BY $column DESC LIMIT 1',
        args,
      );
      return rows.isEmpty ? null : RankedMatch.fromStoredMap(rows.first);
    }

    return (
      bestRpGame: await top(
        'rp_change',
        extraWhere: ' AND $kSqlPlausibleRpChange',
      ),
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

  /// Net ranked RP for [uid] from matches ending in `[start, end)`, or null when
  /// local history demonstrably can't cover that window.
  ///
  /// A rank reset reaches the client as a silent `cumulative_rp` cliff with
  /// `rp_change == 0` on every match across it, so summing per-match RP cannot
  /// see a reset at all.
  ///
  /// `/games` serves a rolling 100-match window, so a player who outplays it
  /// between app opens leaves a hole. Three conditions gate the answer, all
  /// necessary:
  ///
  /// 1. Some row predates [start] — the window isn't merely where recording
  ///    happened to begin.
  /// 2. `cumulative_rp` chains unbroken: each row's running total equals the
  ///    previous plus its own `rp_change`. Catches a hole in the middle.
  /// 3. The newest row's `cumulative_rp` equals [currentRp]. Catches a hole at
  ///    the end, which leaves the chain intact but the endpoint stale.
  ///
  /// The reset itself is the one tolerated break; the accumulator restarts
  /// there, which is what makes this "RP earned since the reset".
  Future<int?> netRpInWindow(
    String uid,
    DateTime start,
    DateTime end, {
    required int currentRp,
  }) async {
    final db = await _open();
    final startMs = start.millisecondsSinceEpoch;

    // Condition 1; also seeds the chain as prevCum below.
    final anchor = await db.rawQuery(
      'SELECT cumulative_rp FROM $table WHERE uid = ? AND end_ms < ? '
      'ORDER BY end_ms DESC LIMIT 1',
      [uid, startMs],
    );
    if (anchor.isEmpty) return null;

    // Pubs included — they carry a cumulative_rp too, so skipping them would
    // punch artificial holes in the chain.
    final rows = await db.rawQuery(
      'SELECT rp_change, cumulative_rp FROM $table '
      "WHERE uid = ? AND game_mode = 'BATTLE_ROYALE' "
      'AND end_ms >= ? AND end_ms < ? ORDER BY end_ms ASC',
      [uid, startMs, end.millisecondsSinceEpoch],
    );
    // No matches in the window is a provable zero, not "can't determine": the
    // anchor above already establishes that local history predates [start], so
    // there is no hole to hide a game in. Returning null here sent a week the
    // player genuinely sat out to the less accurate snapshot estimate.
    if (rows.isEmpty) {
      final anchorCum = (anchor.first['cumulative_rp'] as num?)?.toInt() ?? 0;
      return anchorCum == currentRp ? 0 : null;
    }

    var prevCum = (anchor.first['cumulative_rp'] as num?)?.toInt() ?? 0;
    var net = 0;
    for (final r in rows) {
      final change = (r['rp_change'] as num?)?.toInt() ?? 0;
      final cum = (r['cumulative_rp'] as num?)?.toInt() ?? 0;
      if (cum == prevCum + change) {
        // Matches the neutralisation in [RankedMatch.effectiveRpChange], via
        // the shared predicate - this is the weekly RP figure on My Stats, so
        // it has to agree with the breakdown the user compares it against.
        net += effectiveRpOf(change);
      } else if (change == 0 && cum < prevCum) {
        net = 0; // the reset — start counting from the new floor
      } else {
        return null; // a hole in the chain
      }
      prevCum = cum;
    }
    return prevCum == currentRp ? net : null;
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
  Future<void> appendSnapshotFor(String uid, StatSnapshot snapshot) async {
    final db = await _open();
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

  /// Restores snapshot rows from an export. Idempotent.
  ///
  /// [executor] lets [importBackupData] run this against a [Transaction]
  /// instead of opening its own connection, so it can commit atomically
  /// alongside [importRows]. Defaults to the store's own database for
  /// standalone callers.
  Future<void> importSnapshotRows(
    List<dynamic> rows, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _open();
    final batch = db.batch();
    for (final r in rows) {
      if (r is! Map) continue;
      final uid = r['uid'];
      final tsMs = r['ts_ms'];
      // Both are NOT NULL and form the primary key - a row missing either is
      // unusable, and letting it through would fail the whole batch.
      if (uid is! String || tsMs is! num) continue;
      batch.insert(snapshotTable, {
        'uid': uid,
        'ts_ms': tsMs.toInt(),
        'rp': (r['rp'] as num?)?.toInt() ?? 0,
        'season_id': r['season_id'] as String?,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ── Export / import ────────────────────────────────────────────────────────

  /// Every row across all UIDs — used to build the single-file export.
  Future<List<Map<String, Object?>>> exportRows() async {
    final db = await _open();
    return db.query(table, orderBy: 'start_ms DESC');
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
  };

  /// Restores rows from an export (single JSON file). Idempotent.
  ///
  /// Each row is filtered to [_importableColumns] and skipped unless it carries
  /// a non-empty `id`. Both matter for a file the user picked off disk:
  /// an unknown key would reach SQLite as a column name and fail the entire
  /// batch, and SQLite permits NULL in a non-`INTEGER PRIMARY KEY`, so
  /// id-less rows would insert as duplicates instead of deduping.
  ///
  /// A conflicting id is resolved through [_conflictUpdateSet] — the same
  /// edit-aware, season-upgrade-only rule [upsertAll] applies. This used to
  /// be a plain `INSERT OR REPLACE`, which is a delete-then-insert: any
  /// column absent from the incoming row (or predating it, e.g. a v2 export
  /// with no `season_id` column) went back to NULL, silently demoting a
  /// locally-learned season classification and reverting a hand correction
  /// (`edited_fields` included) the moment an older backup was restored over
  /// a newer one.
  ///
  /// [executor] — see [importSnapshotRows]'s doc for why this exists.
  Future<void> importRows(List<dynamic> rows, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _open();
    final batch = db.batch();
    for (final r in rows) {
      if (r is! Map) continue;
      final id = r['id'];
      if (id is! String || id.isEmpty) continue;
      final row = <String, Object?>{
        for (final col in _importableColumns) col: r[col],
      };
      batch.rawInsert(
        '''
        INSERT INTO $table (
          id, uid, player_name, legend, game_mode, map_key, rp_change,
          cumulative_rp, rank_img, length_secs, start_ms, end_ms,
          is_party_full, trackers, season_id, kills, damage, edited_fields
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
        $_conflictUpdateSet
        ''',
        [
          row['id'],
          row['uid'],
          row['player_name'],
          row['legend'],
          row['game_mode'],
          row['map_key'],
          row['rp_change'],
          row['cumulative_rp'],
          row['rank_img'],
          row['length_secs'],
          row['start_ms'],
          row['end_ms'],
          row['is_party_full'],
          row['trackers'],
          row['season_id'],
          row['kills'],
          row['damage'],
          row['edited_fields'],
        ],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Restores ranked-match rows and RP-snapshot rows from a backup together,
  /// inside one sqflite transaction — both commit or neither does, so a
  /// mid-restore failure can't leave one table updated and the other not.
  /// Prefer this over calling [importRows] / [importSnapshotRows] separately
  /// whenever a backup carries both, which is every version since v3.
  Future<void> importBackupData({
    required List<dynamic> matchRows,
    required List<dynamic> snapshotRows,
  }) async {
    final db = await _open();
    await db.transaction((txn) async {
      await importRows(matchRows, executor: txn);
      await importSnapshotRows(snapshotRows, executor: txn);
    });
  }

  /// Drops both tables. Backs "Clear all data", which promises *everything* -
  /// RP snapshots included, since they are the app's other record of the
  /// player's history.
  Future<void> deleteAll() async {
    final db = await _open();
    await db.delete(table);
    await db.delete(snapshotTable);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
