import 'dart:async';
import 'dart:convert';

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
const Map<String, int> kEndpointCacheTtlMinutes = {
  '/predator': 60,
  '/servers': 5,
  '/maprotation': 15,
};

/// Response cache for [ApiService].
///
/// Durable copy lives in [ApiCacheStore] (SQLite), but [load]/[loadStale] stay
/// synchronous — some callers render on frame 1 and can't wait on disk I/O.
/// Reads are served from an in-memory copy, filled once at startup by
/// [primeFromDisk] (same pattern as `rp_snapshot_storage.dart`'s RP-snapshot
/// cache). A read before priming completes just returns null — deliberate,
/// not a bug.
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

  /// In-memory copy of every persisted entry — what [load]/[loadStale]
  /// actually read. Its length *is* the entry count, so there's no separate
  /// counter that can drift out of sync with it.
  final Map<String, CachedEntry> _cache = {};

  ApiCache(this._store);

  /// Loads every persisted entry into memory. Call once at startup, before
  /// any synchronous [load] is relied on to return non-null.
  Future<void> primeFromDisk() async {
    final rows = await _store.loadAll();
    final corrupt = <String>[];
    for (final entry in rows.entries) {
      final decoded = _tryDecode(entry.value.$1);
      if (decoded == null) {
        // A corrupt row would otherwise keep occupying a slot in
        // [_maxEntries] and re-fail on every subsequent prime.
        corrupt.add(entry.key);
        continue;
      }
      _cache[entry.key] = CachedEntry(
        data: decoded,
        savedAt: DateTime.fromMillisecondsSinceEpoch(entry.value.$2),
      );
    }
    if (corrupt.isNotEmpty) {
      unawaited(_store.removeMany(corrupt));
    }
  }

  Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  /// Saves [data] with a timestamp, then evicts the oldest entries if the
  /// cache has grown past [_maxEntries]. Updates the in-memory copy first, so
  /// a [load] immediately after this returns sees it even before the disk
  /// write settles.
  Future<void> save(String key, dynamic data) async {
    final now = DateTime.now();
    _cache[key] = CachedEntry(data: data, savedAt: now);
    await _store.upsert(key, jsonEncode(data), now.millisecondsSinceEpoch);
    if (_cache.length > _maxEntries) {
      await _evictOldestIfOverCap();
    }
  }

  /// Loads cached data by [key]. Returns null if not found or expired past
  /// the endpoint's TTL.
  CachedEntry? load(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    final ttl = _ttlForKey(key);
    // Millisecond epoch comparison: timezone-safe because both sides use the same
    // internal clock reference regardless of local time zone.
    if (DateTime.now().difference(entry.savedAt).inMinutes > ttl) {
      _cache.remove(key);
      unawaited(_store.remove(key));
      return null;
    }
    return entry;
  }

  /// Loads cached data by [key] regardless of TTL — for the offline-fallback
  /// path, where stale-with-a-banner beats nothing. Returns null only if
  /// there's no entry at all.
  CachedEntry? loadStale(String key) => _cache[key];

  /// Evicts the oldest entries (by saved-at timestamp) once the cache holds
  /// more than [_maxEntries], so unbounded player lookups can't grow the
  /// backing store forever.
  Future<void> _evictOldestIfOverCap() async {
    final overflow = _cache.length - _maxEntries;
    if (overflow <= 0) return;

    final byAge = _cache.entries.toList()
      ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
    final doomed = [for (final e in byAge.take(overflow)) e.key];

    for (final key in doomed) {
      _cache.remove(key);
    }
    await _store.removeMany(doomed);
  }

  /// Removes every cached response — used by "Clear all data".
  Future<void> clear() async {
    _cache.clear();
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
