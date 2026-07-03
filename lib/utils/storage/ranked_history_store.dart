import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/ranked_match.dart';
import '../../models/season_meta.dart';
import '../formatting/season_utils.dart';

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
  static const _version = 2;

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
            season_id TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_uid_start ON $table (uid, start_ms)',
        );
        await db.execute(
          'CREATE INDEX idx_uid_season ON $table (uid, season_id)',
        );
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
      },
    );
    return _db!;
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
      final derivedSeasonId =
          seasons.isNotEmpty ? seasonIdForEndTime(m.endTime, seasons.values) : null;
      batch.rawInsert(
        '''
        INSERT INTO $table (
          id, uid, player_name, legend, game_mode, map_key, rp_change,
          cumulative_rp, rank_img, length_secs, start_ms, end_ms,
          is_party_full, trackers, season_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
    final rows = await db.query(
      table,
      columns: ['id', 'end_ms', 'season_id'],
      where: 'season_id IS NULL OR season_id = ?',
      whereArgs: [kUnknownSeasonId],
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
    return {
      for (final r in rows) r['sid'] as String: (r['c'] as num).toInt(),
    };
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
