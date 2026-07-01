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
  // Guards the one-shot legacy backfill so it runs at most once per store.
  bool _backfilled = false;

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
  /// When [seasons] is supplied each row is stamped with its derived
  /// [season_id] (the split whose window contains the match end time, or
  /// [kOtherSeasonId] if none). Because upserts replace on conflict, the newest
  /// ~100 matches re-stamp their season on every fetch — so a match written
  /// before its split's metadata was known self-corrects on the next refresh.
  /// With no [seasons] the column is left NULL for [backfillSeasonIds] to fill.
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
      if (seasons.isNotEmpty) {
        row['season_id'] = seasonIdForEndTime(m.endTime, seasons.values);
      }
      batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Classifies rows that predate the [season_id] column (NULL) by deriving each
  /// from its end timestamp. A cheap no-op once every row is classified, so it's
  /// safe to call on each launch; skipped entirely until season metadata exists.
  Future<void> backfillSeasonIds(Map<String, SeasonMeta> seasons) async {
    if (_backfilled || seasons.isEmpty) return;
    final db = await _open();
    final rows = await db.query(
      table,
      columns: ['id', 'end_ms'],
      where: 'season_id IS NULL',
    );
    if (rows.isNotEmpty) {
      final batch = db.batch();
      for (final r in rows) {
        final endMs = (r['end_ms'] as num?)?.toInt() ?? 0;
        final endTime = DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true);
        batch.update(
          table,
          {'season_id': seasonIdForEndTime(endTime, seasons.values)},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      await batch.commit(noResult: true);
    }
    _backfilled = true;
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
