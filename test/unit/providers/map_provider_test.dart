import 'dart:convert';

import 'package:apexlytics/models/seasonal_maps.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/map_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockApiService extends Mock implements ApiService {}

/// Covers `SeasonalMapsNotifier.build()`.
///
/// The empty-pool behaviour is **deliberate, not a bug**: once the server's
/// hardcoded map pool goes stale, `/maps` returns
/// `{ranked: [], pubs: []}` on purpose, and the client is meant to pass that
/// straight through — including overwriting whatever was cached — rather
/// than keep serving a stale rotation order that may no longer be accurate.
/// These tests pin that actual, intended behaviour so it doesn't regress
/// (in either direction) unnoticed.
void main() {
  late MockApiService api;
  late SharedPreferences prefs;
  late ProviderContainer container;

  const populatedJson = {
    'ranked': [
      {'id': '2', 'name': "World's Edge"},
    ],
    'pubs': [
      {'id': '2', 'name': "World's Edge"},
    ],
  };
  const emptyJson = {
    'ranked': <Map<String, String>>[],
    'pubs': <Map<String, String>>[],
  };

  Future<void> setUp_({Map<String, Object>? cachedPool}) async {
    SharedPreferences.setMockInitialValues({
      if (cachedPool != null) SeasonalMaps.cacheKey: jsonEncode(cachedPool),
    });
    prefs = await SharedPreferences.getInstance();
    api = MockApiService();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiServiceProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
  }

  test(
    'an empty pool is passed straight through even when a populated cache '
    'exists - not preserved, and not treated as a failure',
    () async {
      await setUp_(cachedPool: populatedJson);
      when(
        () => api.get('/maps', noCache: true),
      ).thenAnswer((_) async => const ApiResult(emptyJson));

      final result = await container.read(seasonalMapsProvider.future);

      expect(result.rankedNames, isEmpty);
      expect(result.pubsNames, isEmpty);
    },
  );

  test(
    'an empty pool overwrites a populated cache (the pool changed, by this '
    'reading)',
    () async {
      await setUp_(cachedPool: populatedJson);
      when(
        () => api.get('/maps', noCache: true),
      ).thenAnswer((_) async => const ApiResult(emptyJson));

      await container.read(seasonalMapsProvider.future);
      // _saveToCache is fire-and-forget (unawaited) - give it a microtask to
      // land before reading it back.
      await Future<void>.delayed(Duration.zero);

      final stillCached = jsonDecode(
        prefs.getString(SeasonalMaps.cacheKey)!,
      ) as Map<String, dynamic>;
      expect((stillCached['ranked'] as List).length, 0);
    },
  );

  test('an empty pool with no prior cache just returns the empty pool', () async {
    await setUp_();
    when(
      () => api.get('/maps', noCache: true),
    ).thenAnswer((_) async => const ApiResult(emptyJson));

    final result = await container.read(seasonalMapsProvider.future);

    expect(result.rankedNames, isEmpty);
    expect(result.pubsNames, isEmpty);
  });

  test('a populated pool is cached for next time', () async {
    await setUp_();
    when(
      () => api.get('/maps', noCache: true),
    ).thenAnswer((_) async => const ApiResult(populatedJson));

    final result = await container.read(seasonalMapsProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(result.rankedNames, ["World's Edge"]);
    expect(prefs.getString(SeasonalMaps.cacheKey), isNotNull);
  });

  test('a network failure falls back to the cache when one exists', () async {
    await setUp_(cachedPool: populatedJson);
    when(
      () => api.get('/maps', noCache: true),
    ).thenThrow(Exception('network down'));

    final result = await container.read(seasonalMapsProvider.future);

    expect(result.rankedNames, ["World's Edge"]);
  });

  // A network failure with no cache at all (`catch (e) { if (cached != null)
  // ...; rethrow; }`) is not covered here: reading a provider's `.future`
  // for a build that rejects on its very first await, with no intervening
  // await before the rethrow, does not resolve reliably under this
  // Riverpod version's test harness (observed to hang past a 30s timeout
  // regardless of whether the read is wrapped in expectLater/throwsA or a
  // manual try/catch) — a harness limitation, not a claim about production
  // behaviour. The same "rethrow when there's nothing to fall back to" shape
  // is exercised successfully for rankedSyncProvider in
  // ranked_sync_outcome_test.dart, where an intervening await before the
  // rethrow avoids whatever this race is.
}
