import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../constants/ranked_map_constants.dart';
import '../../models/ranked_match.dart';
import '../../models/season_meta.dart';
import '../formatting/season_utils.dart';
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
  static const _version = 5;

  // Predicates for the two lazy backfills' "rows still needing work" scope.
  // Each is used verbatim by both a partial index and its backfill query — they
  // must stay byte-identical, or SQLite won't apply the index and the backfill
  // falls back to a full-table scan. Kept as constants so the two can't drift.
  static const _needsKillsDamage = 'kills IS NULL OR damage IS NULL';
  static const _needsSeasonId =
      "season_id IS NULL OR season_id = '$kUnknownSeasonId'";

  final String? _overridePath;
  Database? _db;

  RankedHistoryStore({String? overridePath}) : _overridePath = overridePath;

  Future<Database> _open() async {
    if (_db != null) return _db!;
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
            damage INTEGER
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
        await _createBackfillIndexes(db);
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
          await _createBackfillIndexes(db);
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
      },
    );
    return _db!;
  }

  /// Partial indexes scoped to the "still needs backfilling" rows. SQLite drops
  /// a row from a partial index the moment an UPDATE makes it stop matching the
  /// predicate, so once a backfill fills every legacy row its index is empty and
  /// the backfill's scan touches nothing — no per-sync full table scan, and no
  /// app-side "already done" bookkeeping to maintain or reset.
  Future<void> _createBackfillIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_needs_kills_damage '
      'ON $table (id) WHERE $_needsKillsDamage',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_needs_season_id '
      'ON $table (id) WHERE $_needsSeasonId',
    );
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

  /// Inserts/updates [matches] for [uid]. Idempotent via the primary key.
  ///
  /// Every column except [season_id] is overwritten unconditionally on
  /// conflict. [season_id] only ever *upgrades* — a NULL or [kUnknownSeasonId]
  /// row adopts the freshly-derived id when [seasons] yields a real one, but a
  /// row that already carries a real season id is never touched again, even if
  /// this call's [seasons] is empty/incomplete and would derive [kUnknownSeasonId]
  /// or nothing at all. This is what lets [backfillSeasonIds] and this method
  /// safely re-run as often as needed without ever demoting a correct
  /// classification back to unknown.
  Future<void> upsertAll(
    String uid,
    List<RankedMatch> matches, {
    Map<String, SeasonMeta> seasons = const {},
  }) async {
    if (matches.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final m in matches) {
      final row = m.toStoredMap();
      final derivedSeasonId = seasons.isNotEmpty
          ? seasonIdForEndTime(m.endTime, seasons.values)
          : null;
      batch.rawInsert(
        '''
        INSERT INTO $table (
          id, uid, player_name, legend, game_mode, map_key, rp_change,
          cumulative_rp, rank_img, length_secs, start_ms, end_ms,
          is_party_full, trackers, season_id, kills, damage
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          uid = excluded.uid,
          player_name = excluded.player_name,
          legend = excluded.legend,
          game_mode = excluded.game_mode,
          map_key = excluded.map_key,
          rp_change = excluded.rp_change,
          cumulative_rp = excluded.cumulative_rp,
          rank_img = excluded.rank_img,
          length_secs = excluded.length_secs,
          start_ms = excluded.start_ms,
          end_ms = excluded.end_ms,
          is_party_full = excluded.is_party_full,
          trackers = excluded.trackers,
          kills = excluded.kills,
          damage = excluded.damage,
          season_id = CASE
            WHEN excluded.season_id IS NOT NULL
                 AND excluded.season_id != '$kUnknownSeasonId'
                 AND (season_id IS NULL OR season_id = '$kUnknownSeasonId')
            THEN excluded.season_id
            ELSE season_id
          END
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
          m.kills,
          m.damage,
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

  /// Fills the [kills]/[damage] columns for rows that predate them (v2 → v3
  /// migration left them NULL) by parsing each row's stored `trackers` blob.
  /// New rows are stamped by [upsertAll] on write, so this only ever touches
  /// the legacy backlog and is a cheap no-op once drained — safe to call on
  /// each launch, like [backfillSeasonIds].
  Future<void> backfillKillsDamage() async {
    final db = await _open();
    // Uses [_needsKillsDamage] verbatim so SQLite can serve it from the matching
    // partial index instead of scanning every row.
    final rows = await db.query(
      table,
      columns: ['id', 'trackers'],
      where: _needsKillsDamage,
    );
    if (rows.isEmpty) return;
    final batch = db.batch();
    for (final r in rows) {
      // Only `trackers` matters here; fromStoredMap defaults the rest and
      // exposes the same BR Kills / BR Damage lookup upsert uses.
      final m = RankedMatch.fromStoredMap({'trackers': r['trackers']});
      batch.update(
        table,
        {'kills': m.kills, 'damage': m.damage},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }
    await batch.commit(noResult: true);
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

  // Shared aggregate columns. Net RP zeroes reset outliers; a win/loss is an
  // RP-positive/negative game that isn't a reset artifact — matching
  // `RankedMatch.effectiveRpChange`.
  static const _aggCols =
      '''
      COUNT(*) AS games,
      COALESCE(SUM(kills), 0) AS kills,
      COALESCE(SUM(damage), 0) AS damage,
      COALESCE(SUM(length_secs), 0) AS length_secs,
      COALESCE(SUM(CASE WHEN ABS(rp_change) >= $kRankedOutlierThreshold
                        THEN 0 ELSE rp_change END), 0) AS net_rp,
      COALESCE(SUM(CASE WHEN rp_change > 0 AND rp_change < $kRankedOutlierThreshold
                        THEN 1 ELSE 0 END), 0) AS wins,
      COALESCE(SUM(CASE WHEN rp_change < 0 AND rp_change > -$kRankedOutlierThreshold
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
      totalLengthSecs: (agg['length_secs'] as num).toInt(),
      wins: (agg['wins'] as num).toInt(),
      losses: (agg['losses'] as num).toInt(),
    );
  }

  /// Per-legend breakdown for [uid] across [seasonId] (null = lifetime), sorted
  /// by total RP descending — matching [legendBreakdowns].
  Future<List<LegendBreakdown>> legendBreakdownsFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT legend, $_aggCols FROM $table WHERE $where '
      'GROUP BY legend ORDER BY net_rp DESC',
      args,
    );
    return [
      for (final r in rows)
        LegendBreakdown(
          legend: r['legend'] as String? ?? 'Unknown',
          games: (r['games'] as num).toInt(),
          totalRp: (r['net_rp'] as num).toInt(),
          totalKills: (r['kills'] as num).toInt(),
          totalDamage: (r['damage'] as num).toInt(),
          totalLengthSecs: (r['length_secs'] as num).toInt(),
          wins: (r['wins'] as num).toInt(),
          losses: (r['losses'] as num).toInt(),
        ),
    ];
  }

  /// Per-map breakdown for [uid] across [seasonId] (null = lifetime), sorted by
  /// games descending — matching [mapBreakdowns].
  Future<List<MapBreakdown>> mapBreakdownsFor(
    String uid, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT map_key, $_aggCols FROM $table WHERE $where '
      'GROUP BY map_key ORDER BY games DESC',
      args,
    );
    return [
      for (final r in rows)
        MapBreakdown(
          mapKey: r['map_key'] as String? ?? 'UNKNOWN',
          displayName: rankedMapName(r['map_key'] as String? ?? 'UNKNOWN'),
          games: (r['games'] as num).toInt(),
          totalRp: (r['net_rp'] as num).toInt(),
          totalKills: (r['kills'] as num).toInt(),
          totalDamage: (r['damage'] as num).toInt(),
          totalLengthSecs: (r['length_secs'] as num).toInt(),
          wins: (r['wins'] as num).toInt(),
          losses: (r['losses'] as num).toInt(),
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

  /// Ranked matches for one legend across [seasonId] (null = lifetime), newest
  /// first — the lazy drill-down query the Lifetime Legends tab uses on tap
  /// instead of filtering a whole in-memory history.
  Future<List<RankedMatch>> matchesForLegend(
    String uid,
    String legend, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT * FROM $table WHERE $where AND legend = ? ORDER BY start_ms DESC',
      [...args, legend],
    );
    return rows.map(RankedMatch.fromStoredMap).toList();
  }

  /// Ranked matches for one map across [seasonId] (null = lifetime), newest
  /// first — the lazy drill-down query the Lifetime Maps tab uses on tap.
  Future<List<RankedMatch>> matchesForMap(
    String uid,
    String mapKey, {
    String? seasonId,
  }) async {
    final db = await _open();
    final (where, args) = _rankedScope(uid, seasonId);
    final rows = await db.rawQuery(
      'SELECT * FROM $table WHERE $where AND map_key = ? ORDER BY start_ms DESC',
      [...args, mapKey],
    );
    return rows.map(RankedMatch.fromStoredMap).toList();
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
    if (rows.isEmpty) return null;

    var prevCum = (anchor.first['cumulative_rp'] as num?)?.toInt() ?? 0;
    var net = 0;
    for (final r in rows) {
      final change = (r['rp_change'] as num?)?.toInt() ?? 0;
      final cum = (r['cumulative_rp'] as num?)?.toInt() ?? 0;
      if (cum == prevCum + change) {
        // Matches the neutralisation in [RankedMatch.effectiveRpChange].
        if (change.abs() < kRankedOutlierThreshold) net += change;
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

  /// Every row across all UIDs — used to build the single-file export.
  Future<List<Map<String, Object?>>> exportRows() async {
    final db = await _open();
    return db.query(table, orderBy: 'start_ms DESC');
  }

  /// Restores rows from an export (single JSON file). Idempotent.
  Future<void> importRows(List<dynamic> rows) async {
    final db = await _open();
    final batch = db.batch();
    for (final r in rows) {
      if (r is Map) {
        batch.insert(
          table,
          r.map((k, v) => MapEntry(k.toString(), v)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteAll() async {
    final db = await _open();
    await db.delete(table);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
