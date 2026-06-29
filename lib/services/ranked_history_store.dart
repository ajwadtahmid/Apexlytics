import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/ranked_match.dart';

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
  static const _version = 1;

  final String? _overridePath;
  Database? _db;

  RankedHistoryStore({String? overridePath}) : _overridePath = overridePath;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final path =
        _overridePath ?? p.join(await getDatabasesPath(), _dbName);
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
            trackers TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_uid_start ON $table (uid, start_ms)',
        );
      },
    );
    return _db!;
  }

  /// Inserts/updates [matches] for [uid]. Idempotent via the primary key.
  Future<void> upsertAll(String uid, List<RankedMatch> matches) async {
    if (matches.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final m in matches) {
      batch.insert(
        table,
        m.toStoredMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
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
