import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

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

/// Decodes every row's raw JSON string. Run via [Isolate.run] from
/// [ApiCache.primeFromDisk] — a top-level function with no captured instance
/// state, so it's safe to send to the spawned isolate. [rows] and the
/// returned record are both plain JSON-safe types, which cross the isolate
/// boundary without issue.
///
/// A row that fails to parse, or decodes to a bare `null` (indistinguishable
/// from "couldn't read this" here, and no cached response is ever usefully
/// `null` itself), is reported as corrupt rather than decoded.
({Map<String, (Object? data, int savedAtMs)> decoded, List<String> corrupt})
_decodeCacheRows(Map<String, (String data, int savedAtMs)> rows) {
  final decoded = <String, (Object?, int)>{};
  final corrupt = <String>[];
  for (final entry in rows.entries) {
    Object? value;
    try {
      value = jsonDecode(entry.value.$1);
    } on FormatException {
      corrupt.add(entry.key);
      continue;
    }
    if (value == null) {
      corrupt.add(entry.key);
      continue;
    }
    decoded[entry.key] = (value, entry.value.$2);
  }
  return (decoded: decoded, corrupt: corrupt);
}

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
  ///
  /// Decoding runs off the UI isolate (see [_decodeCacheRows]) — up to
  /// [_maxEntries] arbitrary-sized JSON blobs is real CPU work, called from
  /// [ApiService]'s constructor at startup, contending with first-frame
  /// layout if done inline. Being `unawaited` at the call site doesn't
  /// prevent that on its own: without a real isolate hop, every `jsonDecode`
  /// still runs back-to-back in the one microtask after `loadAll()` resolves.
  Future<void> primeFromDisk() async {
    final rows = await _store.loadAll();
    final result = await Isolate.run(() => _decodeCacheRows(rows));
    for (final entry in result.decoded.entries) {
      final (data, savedAtMs) = entry.value;
      _cache[entry.key] = CachedEntry(
        data: data,
        savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
      );
    }
    if (result.corrupt.isNotEmpty) {
      // A corrupt row would otherwise keep occupying a slot in [_maxEntries]
      // and re-fail on every subsequent prime.
      unawaited(_store.removeMany(result.corrupt));
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
