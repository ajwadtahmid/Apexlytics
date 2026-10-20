import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/player_provider.dart';
import 'package:apexlytics/providers/search_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/services/player_service.dart';
import 'package:apexlytics/utils/formatting/search_utils.dart';
import 'package:apexlytics/utils/refresh_cooldown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

class MockPlayerService extends Mock implements PlayerService {}

/// Pumps a bare [Consumer] and hands back its [WidgetRef], which
/// [refreshAndMarkSynced] takes as its first argument.
Future<WidgetRef> refFrom(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (_, ref, _) {
          captured = ref;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('playerRefreshKey', () {
    test('is stable across casing and surrounding whitespace', () {
      expect(playerRefreshKey('PC', 'Aceu'), playerRefreshKey('PC', 'aceu'));
      expect(playerRefreshKey('PC', 'Aceu'), playerRefreshKey('PC', '  ACEU '));
    });

    test('separates players on the same platform', () {
      expect(
        playerRefreshKey('PC', 'Aceu'),
        isNot(playerRefreshKey('PC', 'Hal')),
      );
    });

    test('separates the same name on different platforms', () {
      expect(
        playerRefreshKey('PC', 'Aceu'),
        isNot(playerRefreshKey('PS4', 'Aceu')),
      );
    });

    test('is distinct from the badge identity key', () {
      // playerSessionKey keeps the raw query, so the two must not be swapped
      // for one another at a call site.
      expect(
        playerRefreshKey('PC', 'Aceu'),
        isNot(playerSessionKey('PC', 'Aceu')),
      );
    });
  });

  group('refreshAndMarkSynced when throttled', () {
    late MockPlayerService service;
    late RefreshCooldown cooldown;
    late ProviderContainer container;

    setUp(() {
      service = MockPlayerService();
      cooldown = RefreshCooldown(duration: const Duration(seconds: 10));
      container = ProviderContainer(
        overrides: [refreshCooldownProvider.overrideWithValue(cooldown)],
      );
      addTearDown(container.dispose);
    });

    testWidgets('reports success without calling the service', (tester) async {
      cooldown.tryFire(playerRefreshKey('PC', 'uid999'));
      final ref = await refFrom(tester, container);

      final result = await refreshAndMarkSynced(
        ref,
        service,
        'uid999',
        'PC',
        true,
      );

      expect(result, isTrue);
      verifyNever(() => service.getPlayerStatsByUid(any(), any()));
      verifyNever(() => service.getPlayerStats(any(), any()));
    });

    testWidgets('marks a UID lookup synced under its UID', (tester) async {
      cooldown.tryFire(playerRefreshKey('PC', 'uid999'));
      final ref = await refFrom(tester, container);

      await refreshAndMarkSynced(ref, service, 'uid999', 'PC', true);

      expect(container.read(sessionRefreshedProvider), contains('uid999'));
    });

    testWidgets('marks a name lookup synced under its session key', (
      tester,
    ) async {
      cooldown.tryFire(playerRefreshKey('PC', 'Aceu'));
      final ref = await refFrom(tester, container);

      await refreshAndMarkSynced(ref, service, 'Aceu', 'PC', false);

      expect(
        container.read(sessionRefreshedProvider),
        contains(playerSessionKey('PC', 'Aceu')),
      );
    });

    testWidgets('a differently cased query hits the same cooldown', (
      tester,
    ) async {
      // The lookup form submits what the user typed; the favorites refresh
      // submits the stored name. Both land on one window.
      cooldown.tryFire(playerRefreshKey('PC', 'Aceu'));
      final ref = await refFrom(tester, container);

      await refreshAndMarkSynced(ref, service, 'ACEU', 'PC', false);

      verifyNever(() => service.getPlayerStats(any(), any()));
    });
  });

  group('refreshAndMarkSynced after a fetch', () {
    const params = (query: 'uid123', platform: 'PC', searchByUid: true);
    final cachedAt = DateTime(2026, 10, 1, 9);

    late MockPlayerService service;
    late ProviderContainer container;

    setUp(() async {
      // One favorite, the player these lookups are for.
      SharedPreferences.setMockInitialValues({
        'search_favorites':
            '[{"query":"TestPlayer","platform":"PC","uid":"uid123"}]',
      });
      final prefs = await SharedPreferences.getInstance();
      service = MockPlayerService();
      // The cache always answers with its save time, as the real one does.
      when(
        () => service.getCachedStats(
          any(),
          any(),
          searchByUid: any(named: 'searchByUid'),
        ),
      ).thenReturn(ApiResult(buildStats(rankScore: 1000), staleAt: cachedAt));
      container = ProviderContainer(
        overrides: [
          playerServiceProvider.overrideWithValue(service),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      // Keep the provider alive across the refresh, as an open result page does.
      final sub = container.listen(searchPlayerProvider(params), (_, _) {});
      addTearDown(sub.close);
    });

    testWidgets('a live answer replaces the cached, stale one', (tester) async {
      when(
        () => service.getPlayerStatsByUid(any(), any()),
      ).thenAnswer((_) async => ApiResult(buildStats(rankScore: 1100)));
      final ref = await refFrom(tester, container);
      await tester.runAsync(() async {
        final first = await container.read(searchPlayerProvider(params).future);
        expect(first.staleAt, cachedAt);

        expect(
          await refreshAndMarkSynced(ref, service, 'uid123', 'PC', true),
          isTrue,
        );
      });

      final after = container.read(searchPlayerProvider(params)).requireValue;
      expect(after.staleAt, isNull);
      expect(after.data.rankScore, 1100);
    });

    testWidgets('a live answer is kept on the favorite, for its card', (
      tester,
    ) async {
      when(() => service.getPlayerStatsByUid(any(), any())).thenAnswer(
        (_) async => ApiResult(buildStats(rank: 'Diamond', rankScore: 11000)),
      );
      final ref = await refFrom(tester, container);
      await tester.runAsync(() async {
        await refreshAndMarkSynced(ref, service, 'uid123', 'PC', true);
      });

      final snapshot = container
          .read(searchStateProvider)
          .favorites
          .single
          .snapshot;
      expect(snapshot?.rankScore, 11000);
      expect(snapshot?.rank, 'Diamond');
    });

    testWidgets('a stale fallback leaves what the favorite kept alone', (
      tester,
    ) async {
      when(() => service.getPlayerStatsByUid(any(), any())).thenAnswer(
        (_) async => ApiResult(
          buildStats(rankScore: 1000),
          staleAt: DateTime(2026, 10, 1, 10),
        ),
      );
      final ref = await refFrom(tester, container);
      await tester.runAsync(() async {
        await refreshAndMarkSynced(ref, service, 'uid123', 'PC', true);
      });

      expect(
        container.read(searchStateProvider).favorites.single.snapshot,
        isNull,
      );
    });

    testWidgets('a player who is not a favorite is not saved anywhere', (
      tester,
    ) async {
      await container.read(searchStateProvider.notifier).clearFavorites();
      when(
        () => service.getPlayerStatsByUid(any(), any()),
      ).thenAnswer((_) async => ApiResult(buildStats(rankScore: 1100)));
      final ref = await refFrom(tester, container);
      await tester.runAsync(() async {
        await refreshAndMarkSynced(ref, service, 'uid123', 'PC', true);
      });

      expect(container.read(searchStateProvider).favorites, isEmpty);
    });

    testWidgets('a stale fallback is neither success nor "synced"', (
      tester,
    ) async {
      when(() => service.getPlayerStatsByUid(any(), any())).thenAnswer(
        (_) async => ApiResult(
          buildStats(rankScore: 1000),
          staleAt: DateTime(2026, 10, 1, 10),
        ),
      );
      final ref = await refFrom(tester, container);

      late bool result;
      await tester.runAsync(() async {
        await container.read(searchPlayerProvider(params).future);
        result = await refreshAndMarkSynced(ref, service, 'uid123', 'PC', true);
      });

      // Offline, nothing was fetched: the favourite must not turn "synced".
      expect(result, isFalse);
      expect(container.read(sessionRefreshedProvider), isEmpty);
    });

    testWidgets('a stale fallback stays marked stale', (tester) async {
      final fallbackAt = DateTime(2026, 10, 1, 10);
      when(() => service.getPlayerStatsByUid(any(), any())).thenAnswer(
        (_) async =>
            ApiResult(buildStats(rankScore: 1000), staleAt: fallbackAt),
      );
      final ref = await refFrom(tester, container);
      await tester.runAsync(() async {
        await container.read(searchPlayerProvider(params).future);
        await refreshAndMarkSynced(ref, service, 'uid123', 'PC', true);
      });

      final after = container.read(searchPlayerProvider(params)).requireValue;
      expect(after.staleAt, cachedAt);
    });
  });
}
