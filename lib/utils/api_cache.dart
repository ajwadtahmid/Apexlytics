import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

class ApiCache {
  final SharedPreferences _prefs;
  static const _cacheKeyPrefix = 'api_cache:';
  static const _cacheTimestampKeyPrefix = 'api_cache_ts:';
  // Default TTL: 24 h — useful offline but overridden per endpoint above.
  static const defaultMaxAgeMinutes = 24 * 60;
  // Caps disk growth from arbitrary-player lookups (search/compare) that each
  // write a permanent entry with no TTL-driven cleanup. Oldest entries evict
  // first once the cap is exceeded.
  static const _maxEntries = 150;

  ApiCache(this._prefs);

  // Approximate entry count, tracked in memory so [save] doesn't need to scan
  // every SharedPreferences key on every write. Lazily initialized from a real
  // scan on first use, then kept roughly in sync; [_evictOldestIfOverCap]
  // resyncs it exactly whenever it actually runs.
  int? _entryCount;

  /// Saves [data] with a timestamp, then evicts the oldest entries if the
  /// cache has grown past [_maxEntries].
  Future<void> save(String key, dynamic data) async {
    final tsKey = '$_cacheTimestampKeyPrefix$key';
    final isNewEntry = !_prefs.containsKey(tsKey);
    await _prefs.setString('$_cacheKeyPrefix$key', jsonEncode(data));
    await _prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
    if (isNewEntry) {
      _entryCount = (_entryCount ?? _scanEntryCount()) + 1;
    }
    if ((_entryCount ?? 0) > _maxEntries) {
      await _evictOldestIfOverCap();
    }
  }

  int _scanEntryCount() => _prefs
      .getKeys()
      .where((k) => k.startsWith(_cacheTimestampKeyPrefix))
      .length;

  /// Loads cached data by [key]. Returns null if not found or expired past the endpoint's TTL.
  CachedEntry? load(String key) {
    final raw = _prefs.getString('$_cacheKeyPrefix$key');
    final ts = _prefs.getInt('$_cacheTimestampKeyPrefix$key');
    if (raw == null || ts == null) return null;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(ts);
    final ttl = _ttlForKey(key);
    // Millisecond epoch comparison: timezone-safe because both sides use the same
    // internal clock reference regardless of local time zone.
    if (DateTime.now().difference(savedAt).inMinutes > ttl) {
      unawaited(_removeEntry(key));
      return null;
    }
    return _decode(raw, savedAt);
  }

  /// Loads cached data by [key] regardless of TTL — for the offline-fallback
  /// path, where stale-with-a-banner beats nothing. Returns null only if
  /// there's no entry at all.
  CachedEntry? loadStale(String key) {
    final raw = _prefs.getString('$_cacheKeyPrefix$key');
    final ts = _prefs.getInt('$_cacheTimestampKeyPrefix$key');
    if (raw == null || ts == null) return null;
    return _decode(raw, DateTime.fromMillisecondsSinceEpoch(ts));
  }

  CachedEntry? _decode(String raw, DateTime savedAt) {
    try {
      return CachedEntry(data: jsonDecode(raw), savedAt: savedAt);
    } on FormatException {
      return null;
    }
  }

  Future<void> _removeEntry(String key) => Future.wait([
        _prefs.remove('$_cacheKeyPrefix$key'),
        _prefs.remove('$_cacheTimestampKeyPrefix$key'),
      ]);

  /// Evicts the oldest entries (by saved-at timestamp) once the cache holds
  /// more than [_maxEntries], so unbounded player lookups can't grow the
  /// `SharedPreferences` backing store forever.
  Future<void> _evictOldestIfOverCap() async {
    final tsKeys = _prefs
        .getKeys()
        .where((k) => k.startsWith(_cacheTimestampKeyPrefix))
        .toList();
    final overflow = tsKeys.length - _maxEntries;
    if (overflow <= 0) {
      _entryCount = tsKeys.length;
      return;
    }

    final byAge = tsKeys
        .map((k) => MapEntry(k, _prefs.getInt(k) ?? 0))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (final entry in byAge.take(overflow)) {
      final key = entry.key.substring(_cacheTimestampKeyPrefix.length);
      await _removeEntry(key);
    }
    _entryCount = tsKeys.length - overflow;
  }

  /// Removes every cached response and its timestamp — used by "Clear all data".
  Future<void> clear() async {
    final keys = _prefs.getKeys().where(
      (k) => k.startsWith(_cacheKeyPrefix) || k.startsWith(_cacheTimestampKeyPrefix),
    );
    for (final key in keys.toList()) {
      await _prefs.remove(key);
    }
    _entryCount = 0;
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
