import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Durable backing store for [ApiCache] — the disk half of the API response
/// cache. Its own small database, independent of `ranked_history.db`, so a
/// bug in one can't touch the other.
///
/// `key`/`data`/`saved_at` live in one row per entry — a single row can't
/// have a data value with no matching timestamp, unlike a two-key scheme
/// would allow.
class ApiCacheStore {
  static const _dbName = 'api_cache.db';
  static const _table = 'cache';
  static const _version = 1;

  final String? _overridePath;
  Database? _db;

  // The in-flight open, held only while one is running — same reasoning as
  // RankedHistoryStore._open: several callers could race into this during
  // the same microtask drain (priming at startup, a save mid-request).
  Future<Database>? _opening;

  // this._overridePath can't be a named parameter here — private identifiers
  // aren't callable from outside the library, and `overridePath:` must stay
  // public for callers (mirrors RankedHistoryStore's same constructor shape).
  // ignore: prefer_initializing_formals
  ApiCacheStore({String? overridePath}) : _overridePath = overridePath;

  Future<Database> _open() {
    final db = _db;
    if (db != null) return Future.value(db);
    return _opening ??= _doOpen().whenComplete(() => _opening = null);
  }

  Future<Database> _doOpen() async {
    final path = _overridePath ?? await _resolveDbPath();
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            key TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            saved_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// Mirrors RankedHistoryStore._resolveDbPath — mobile's native sqflite
  /// factory returns a guaranteed-existing directory; the FFI factory used on
  /// desktop needs a real per-user app-support directory instead, created if
  /// missing.
  Future<String> _resolveDbPath() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return p.join(await getDatabasesPath(), _dbName);
    }
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return p.join(dir.path, _dbName);
  }

  /// Every persisted entry, keyed by cache key — read once at startup to
  /// prime [ApiCache]'s in-memory copy. Reads afterwards are served from
  /// memory, not this store, so the disk round-trip only happens once.
  Future<Map<String, (String data, int savedAtMs)>> loadAll() async {
    final db = await _open();
    final rows = await db.query(_table);
    return {
      for (final r in rows)
        r['key'] as String: (
          r['data'] as String,
          (r['saved_at'] as num).toInt(),
        ),
    };
  }

  /// Inserts or overwrites the row for [key].
  Future<void> upsert(String key, String data, int savedAtMs) async {
    final db = await _open();
    await db.insert(_table, {
      'key': key,
      'data': data,
      'saved_at': savedAtMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(String key) async {
    final db = await _open();
    await db.delete(_table, where: 'key = ?', whereArgs: [key]);
  }

  /// Batched [remove] for eviction sweeps (cap overflow, corrupt rows found
  /// while priming) — one commit instead of one round-trip per key.
  Future<void> removeMany(Iterable<String> keys) async {
    if (keys.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final key in keys) {
      batch.delete(_table, where: 'key = ?', whereArgs: [key]);
    }
    await batch.commit(noResult: true);
  }

  /// Drops every cached response — used by "Clear all data".
  Future<void> clear() async {
    final db = await _open();
    await db.delete(_table);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
