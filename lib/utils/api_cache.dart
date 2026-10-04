import 'dart:async';
import 'dart:convert';

import 'app_logger.dart';
import 'storage/api_cache_store.dart';

class ApiResult<T> {
  final T data;
  final DateTime? staleAt;
  const ApiResult(this.data, {this.staleAt});
}

class CachedEntry {
  final dynamic data;
  final DateTime savedAt;
  const CachedEntry({required this.data, required this.savedAt});
}

/// Per-endpoint TTL overrides (in minutes). Endpoints not listed fall back to
/// [ApiCache.defaultMaxAgeMinutes].
///
/// `/maprotation` deliberately has no entry: [MapService.getMapRotation]
/// always fetches with `noCache: true`, and the background-fetch path
/// bypasses this cache entirely — no caller could ever hit its TTL.
const Map<String, int> kEndpointCacheTtlMinutes = {
  '/predator': 60,
  '/servers': 5,
};

/// One persisted response as held in memory: the JSON text exactly as stored,
/// not the decoded tree. A decoded copy of a player payload is several times
/// the size of its text, and up to [ApiCache._maxEntries] of them used to be
/// pinned for the life of the app.
class _RawEntry {
  final String json;
  final DateTime savedAt;
  const _RawEntry(this.json, this.savedAt);
}

/// Response cache for [ApiService].
///
/// Durable copy lives in [ApiCacheStore] (SQLite), but [load]/[loadStale] stay
/// synchronous — some callers render on frame 1 and can't wait on disk I/O.
/// Reads are served from an in-memory copy of the stored JSON text, filled once
/// at startup by [primeFromDisk] (same pattern as `rp_snapshot_storage.dart`'s
/// RP-snapshot cache). A read before priming completes just returns null —
/// deliberate, not a bug.
///
/// Only the most recently used [_maxDecoded] entries are kept decoded; the rest
/// are parsed on demand, so memory is bounded by the text, not by 150 object
/// graphs, and startup does no decoding at all.
///
/// Backed by SQLite instead of SharedPreferences so a large cache doesn't get
/// parsed on the main thread at every app launch.
class ApiCache {
  final ApiCacheStore _store;

  // Default TTL: 24 h — useful offline but overridden per endpoint above.
  static const defaultMaxAgeMinutes = 24 * 60;

  // Caps disk growth from arbitrary-player lookups (search/compare) that each
  // write a permanent entry with no TTL-driven cleanup. Oldest entries evict
  // first once the cap is exceeded.
  static const _maxEntries = 150;

  /// How many entries stay decoded. Enough for what a screen re-reads on every
  /// rebuild (My Stats, a few favourites, the home cards).
  static const _maxDecoded = 12;

  /// In-memory copy of every persisted entry — what [load]/[loadStale]
  /// actually read. Its length *is* the entry count, so there's no separate
  /// counter that can drift out of sync with it.
  final Map<String, _RawEntry> _entries = {};

  /// Least recently used first (insertion order). A hit is only trusted while
  /// its [CachedEntry.savedAt] still matches the raw entry's.
  final Map<String, CachedEntry> _decoded = {};

  ApiCache(this._store);

  /// Loads every persisted entry into memory as text. Call once at startup,
  /// before any synchronous [load] is relied on to return non-null.
  ///
  /// Nothing is decoded here: a row that doesn't parse is found, and dropped
  /// from disk, when something first reads it (see [_read]).
  ///
  /// Unawaited at startup, so a real request can [save] while this is still
  /// reading — what it read is then stale and must not replace a fresher
  /// entry, or [load] would later expire it and delete the fresh row from disk
  /// along with it.
  Future<void> primeFromDisk() async {
    final generation = _generation;
    final rows = await _store.loadAll();
    // Cleared while priming: everything read predates the clear.
    if (generation != _generation) return;
    for (final entry in rows.entries) {
      final (json, savedAtMs) = entry.value;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
      final current = _entries[entry.key];
      if (current != null && !current.savedAt.isBefore(savedAt)) continue;
      _entries[entry.key] = _RawEntry(json, savedAt);
    }
  }

  /// Bumped by [clear], so a [primeFromDisk] already reading when the cache
  /// was cleared doesn't put them back, and so an in-flight response can tell its [save]
  /// is stale.
  int _generation = 0;

  /// Read before a request and passed back to [save] as `ifGeneration`.
  int get generation => _generation;

  /// Saves [data] with a timestamp, then evicts the oldest entries if the
  /// cache has grown past [_maxEntries]. Updates the in-memory copy first, so
  /// a [load] immediately after this returns sees it even before the disk
  /// write settles.
  ///
  /// [ifGeneration] is the [generation] read before the request; if [clear] ran since, the
  /// response is dropped.
  Future<void> save(String key, dynamic data, {int? ifGeneration}) async {
    if (ifGeneration != null && ifGeneration != _generation) return;
    final startedAt = _generation;
    final now = DateTime.now();
    final json = jsonEncode(data);
    _entries[key] = _RawEntry(json, now);
    // The object just fetched is the freshest decoded copy there is.
    _remember(key, CachedEntry(data: data, savedAt: now));
    await _store.upsert(key, json, now.millisecondsSinceEpoch);
    if (startedAt != _generation) {
      // Cleared while the row was being written; the clear may have run first.
      await _store.remove(key);
      return;
    }
    if (_entries.length > _maxEntries) {
      await _evictOldestIfOverCap();
    }
  }

  /// Loads cached data by [key]. Returns null if not found or expired past
  /// the endpoint's TTL.
  ///
  /// An expired entry is kept: [loadStale] is the offline fallback and needs
  /// it. The entry cap bounds growth.
  CachedEntry? load(String key) {
    final entry = _read(key);
    if (entry == null) return null;
    final ttl = _ttlForKey(key);
    // Millisecond epoch comparison: timezone-safe because both sides use the same
    // internal clock reference regardless of local time zone.
    if (DateTime.now().difference(entry.savedAt).inMinutes > ttl) return null;
    return entry;
  }

  /// Loads cached data by [key] regardless of TTL — for the offline-fallback
  /// path, where stale-with-a-banner beats nothing. Returns null only if
  /// there's no entry at all.
  CachedEntry? loadStale(String key) => _read(key);

  /// The decoded entry for [key], from the hot set or parsed from its stored
  /// text. An entry whose text doesn't parse (or is a bare `null`, which no
  /// real response is) is dropped from memory and disk rather than left to
  /// fail on every read and hold a slot in [_maxEntries].
  CachedEntry? _read(String key) {
    final raw = _entries[key];
    if (raw == null) return null;

    final hot = _decoded[key];
    if (hot != null && hot.savedAt == raw.savedAt) {
      _remember(key, hot); // a read counts as use
      return hot;
    }

    Object? value;
    try {
      value = jsonDecode(raw.json);
    } on FormatException {
      value = null;
    }
    if (value == null) {
      _entries.remove(key);
      _decoded.remove(key);
      unawaited(
        _store.remove(key).catchError((Object e) {
          log.w('API cache: dropping a corrupt row failed', error: e);
        }),
      );
      return null;
    }
    final entry = CachedEntry(data: value, savedAt: raw.savedAt);
    _remember(key, entry);
    return entry;
  }

  /// Marks [entry] the most recently used decoded copy, evicting the least
  /// recently used past [_maxDecoded].
  void _remember(String key, CachedEntry entry) {
    _decoded.remove(key);
    _decoded[key] = entry;
    while (_decoded.length > _maxDecoded) {
      _decoded.remove(_decoded.keys.first);
    }
  }

  /// Evicts the oldest entries (by saved-at timestamp) once the cache holds
  /// more than [_maxEntries], so unbounded player lookups can't grow the
  /// backing store forever.
  Future<void> _evictOldestIfOverCap() async {
    final overflow = _entries.length - _maxEntries;
    if (overflow <= 0) return;

    final byAge = _entries.entries.toList()
      ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
    final doomed = [for (final e in byAge.take(overflow)) e.key];

    for (final key in doomed) {
      _entries.remove(key);
      _decoded.remove(key);
    }
    await _store.removeMany(doomed);
  }

  /// Removes every cached response — used by "Clear all data".
  Future<void> clear() async {
    _generation++;
    _entries.clear();
    _decoded.clear();
    await _store.clear();
  }

  /// Resolves TTL by matching the key against [kEndpointCacheTtlMinutes].
  /// Keys are cache keys (endpoint + params), so we match on prefix.
  static int _ttlForKey(String key) {
    for (final entry in kEndpointCacheTtlMinutes.entries) {
      if (key.startsWith(entry.key)) return entry.value;
    }
    return defaultMaxAgeMinutes;
  }
}
