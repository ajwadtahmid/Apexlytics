import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:apexlytics/utils/api_cache.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';

void main() {
  // sqflite has no native binding under `flutter test` (host VM) — use FFI.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Bare `inMemoryDatabasePath` (':memory:') is not enough isolation here:
  // sqflite_common_ffi opens in-memory databases in shared-cache mode, so
  // every store opened with that literal path in this process aliases to the
  // *same* underlying database — rows from an earlier test in this file
  // silently show up in a later one's. A uniquely-named in-memory URI per
  // store keeps each test's data private.
  var dbCounter = 0;
  ApiCacheStore freshStore() => ApiCacheStore(
    overridePath: 'file:api_cache_test_${dbCounter++}?mode=memory&cache=shared',
  );

  group('ApiCache.save / load', () {
    test('load returns null when nothing stored', () async {
      final cache = ApiCache(freshStore());
      expect(cache.load('somekey'), isNull);
    });

    test('save then load returns the stored data', () async {
      final cache = ApiCache(freshStore());
      await cache.save('mykey', {'foo': 'bar'});
      final entry = cache.load('mykey');
      expect(entry, isNotNull);
      expect((entry!.data as Map<String, dynamic>)['foo'], 'bar');
    });

    test('load returns null for a corrupt row picked up at prime time', () async {
      final store = freshStore();
      await store.upsert('key', 'bad-json', DateTime.now().millisecondsSinceEpoch);
      final cache = ApiCache(store);
      await cache.primeFromDisk();
      expect(cache.load('key'), isNull);
    });

    test('a corrupt row is dropped from disk too, not left to re-fail forever', () async {
      final store = freshStore();
      await store.upsert('key', 'bad-json', DateTime.now().millisecondsSinceEpoch);
      final cache = ApiCache(store);
      await cache.primeFromDisk();
      expect(cache.load('key'), isNull);
      // The removal is fire-and-forget; let it settle before asserting.
      await Future<void>.delayed(Duration.zero);
      final remaining = await store.loadAll();
      expect(remaining.containsKey('key'), isFalse);
    });

    test('savedAt is approximately now', () async {
      final before = DateTime.now();
      final cache = ApiCache(freshStore());
      await cache.save('ts_key', {});
      final entry = cache.load('ts_key');
      expect(
        entry!.savedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('an unprimed cache reads empty rather than throwing', () async {
      // No primeFromDisk() call — mirrors app startup before priming
      // completes (see ApiCache's doc comment). Deliberate, not a bug.
      final store = freshStore();
      await store.upsert('key', jsonEncode({'a': 1}), DateTime.now().millisecondsSinceEpoch);
      final cache = ApiCache(store);
      expect(cache.load('key'), isNull);
      expect(cache.loadStale('key'), isNull);
    });
  });

  group('Per-endpoint TTL', () {
    Future<ApiCache> primedCacheWithAgedEntry(String key, int minutesAgo) async {
      final store = freshStore();
      final ts = DateTime.now()
          .subtract(Duration(minutes: minutesAgo))
          .millisecondsSinceEpoch;
      await store.upsert(key, jsonEncode({'data': 1}), ts);
      final cache = ApiCache(store);
      await cache.primeFromDisk();
      return cache;
    }

    test('/servers entry expires after 5 minutes', () async {
      final cache = await primedCacheWithAgedEntry('/servers', 6);
      expect(cache.load('/servers'), isNull);
    });

    test('/servers entry is fresh within 5 minutes', () async {
      final cache = await primedCacheWithAgedEntry('/servers', 4);
      expect(cache.load('/servers'), isNotNull);
    });

    test('/predator entry expires after 60 minutes', () async {
      final cache = await primedCacheWithAgedEntry('/predator', 61);
      expect(cache.load('/predator'), isNull);
    });

    test('/predator entry is fresh within 60 minutes', () async {
      final cache = await primedCacheWithAgedEntry('/predator', 59);
      expect(cache.load('/predator'), isNotNull);
    });

    test('/maprotation entry expires after 15 minutes', () async {
      final cache = await primedCacheWithAgedEntry('/maprotation', 16);
      expect(cache.load('/maprotation'), isNull);
    });

    test('unknown endpoint falls back to 24h TTL', () async {
      // 23h 50m ago — should still be fresh under the 24h default.
      final cache = await primedCacheWithAgedEntry('/player', 23 * 60 + 50);
      expect(cache.load('/player'), isNotNull);
    });

    test('unknown endpoint expires after 24h', () async {
      final cache = await primedCacheWithAgedEntry('/player', 24 * 60 + 1);
      expect(cache.load('/player'), isNull);
    });

    test(
      'load() prunes an expired entry so it stops counting toward the cap',
      () async {
        final store = freshStore();
        final ts = DateTime.now()
            .subtract(const Duration(minutes: 24 * 60 + 1))
            .millisecondsSinceEpoch;
        await store.upsert('/player', jsonEncode({'data': 1}), ts);
        final cache = ApiCache(store);
        await cache.primeFromDisk();
        expect(cache.load('/player'), isNull);
        await Future<void>.delayed(Duration.zero);
        final remaining = await store.loadAll();
        expect(remaining.containsKey('/player'), isFalse);
      },
    );
  });

  group('Eviction cap', () {
    test('keeps the cache size at or under the cap after many saves', () async {
      final store = freshStore();
      final cache = ApiCache(store);
      for (var i = 0; i < 160; i++) {
        await cache.save('/player/uid$i', {'i': i});
      }
      final persisted = await store.loadAll();
      expect(persisted.length, lessThanOrEqualTo(150));
    });

    test('evicts the oldest entries first, keeping the newest', () async {
      final store = freshStore();
      // Pre-populate 150 entries (the cap) with deterministic, ascending
      // timestamps so uid0 is unambiguously the oldest, then prime them into
      // the cache's in-memory copy.
      for (var i = 0; i < 150; i++) {
        await store.upsert('/player/uid$i', '{"i":$i}', i);
      }
      final cache = ApiCache(store);
      await cache.primeFromDisk();

      // One more save (real, later timestamp) pushes the cache over the cap.
      await cache.save('/player/uid150', {'i': 150});

      expect(cache.load('/player/uid0'), isNull);
      expect(cache.load('/player/uid150'), isNotNull);
    });
  });
}
