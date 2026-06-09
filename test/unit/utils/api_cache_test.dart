import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/utils/api_cache.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ApiCache.save / load', () {
    test('load returns null when nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = ApiCache(prefs);
      expect(cache.load('somekey'), isNull);
    });

    test('save then load returns the stored data', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = ApiCache(prefs);
      await cache.save('mykey', {'foo': 'bar'});
      final entry = cache.load('mykey');
      expect(entry, isNotNull);
      expect((entry!.data as Map<String, dynamic>)['foo'], 'bar');
    });

    test('load returns null for corrupted JSON', () async {
      SharedPreferences.setMockInitialValues({'api_cache:key': 'bad-json'});
      final prefs = await SharedPreferences.getInstance();
      final cache = ApiCache(prefs);
      // Simulate a valid timestamp so TTL does not evict first.
      await prefs.setInt(
        'api_cache_ts:key',
        DateTime.now().millisecondsSinceEpoch,
      );
      expect(cache.load('key'), isNull);
    });

    test('load returns null when timestamp is missing', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = ApiCache(prefs);
      await prefs.setString('api_cache:key', jsonEncode({'x': 1}));
      // No timestamp key set → treat as missing.
      expect(cache.load('key'), isNull);
    });

    test('savedAt is approximately now', () async {
      final before = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final cache = ApiCache(prefs);
      await cache.save('ts_key', {});
      final entry = cache.load('ts_key');
      expect(
        entry!.savedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('Per-endpoint TTL', () {
    Future<void> setOldEntry(
      SharedPreferences prefs,
      String key,
      int minutesAgo,
    ) async {
      final ts = DateTime.now()
          .subtract(Duration(minutes: minutesAgo))
          .millisecondsSinceEpoch;
      await prefs.setString('api_cache:$key', jsonEncode({'data': 1}));
      await prefs.setInt('api_cache_ts:$key', ts);
    }

    test('/servers entry expires after 5 minutes', () async {
      final prefs = await SharedPreferences.getInstance();
      await setOldEntry(prefs, '/servers', 6);
      final cache = ApiCache(prefs);
      expect(cache.load('/servers'), isNull);
    });

    test('/servers entry is fresh within 5 minutes', () async {
      final prefs = await SharedPreferences.getInstance();
      await setOldEntry(prefs, '/servers', 4);
      final cache = ApiCache(prefs);
      expect(cache.load('/servers'), isNotNull);
    });

    test('/predator entry expires after 60 minutes', () async {
      final prefs = await SharedPreferences.getInstance();
      await setOldEntry(prefs, '/predator', 61);
      final cache = ApiCache(prefs);
      expect(cache.load('/predator'), isNull);
    });

    test('/predator entry is fresh within 60 minutes', () async {
      final prefs = await SharedPreferences.getInstance();
      await setOldEntry(prefs, '/predator', 59);
      final cache = ApiCache(prefs);
      expect(cache.load('/predator'), isNotNull);
    });

    test('/maprotation entry expires after 15 minutes', () async {
      final prefs = await SharedPreferences.getInstance();
      await setOldEntry(prefs, '/maprotation', 16);
      final cache = ApiCache(prefs);
      expect(cache.load('/maprotation'), isNull);
    });

    test('unknown endpoint falls back to 24h TTL', () async {
      final prefs = await SharedPreferences.getInstance();
      // 23h 50m ago — should still be fresh under the 24h default.
      await setOldEntry(prefs, '/player', 23 * 60 + 50);
      final cache = ApiCache(prefs);
      expect(cache.load('/player'), isNotNull);
    });

    test('unknown endpoint expires after 24h', () async {
      final prefs = await SharedPreferences.getInstance();
      await setOldEntry(prefs, '/player', 24 * 60 + 1);
      final cache = ApiCache(prefs);
      expect(cache.load('/player'), isNull);
    });
  });
}
