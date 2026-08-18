import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/player_provider.dart';
import 'package:apexlytics/services/player_service.dart';
import 'package:apexlytics/utils/formatting/search_utils.dart';
import 'package:apexlytics/utils/refresh_cooldown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
}
