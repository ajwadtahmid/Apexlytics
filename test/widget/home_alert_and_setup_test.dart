import 'dart:async';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/map_rotation.dart';
import 'package:apexlytics/models/news_article.dart';
import 'package:apexlytics/models/predator.dart';
import 'package:apexlytics/models/seasonal_maps.dart';
import 'package:apexlytics/models/server_status.dart';
import 'package:apexlytics/constants/map_constants.dart';
import 'package:apexlytics/providers/map_provider.dart';
import 'package:apexlytics/providers/navigation_provider.dart';
import 'package:apexlytics/providers/news_provider.dart';
import 'package:apexlytics/providers/predator_provider.dart';
import 'package:apexlytics/providers/server_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/home/home_screen.dart';
import 'package:apexlytics/utils/api_cache.dart' show ApiResult;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

MapMode _mode(String map) =>
    MapMode(map: map, remainingSecs: 1800, durationMins: 60, asset: '');

/// The season's map pool, without asking the server for it.
class _Seasonal extends SeasonalMapsNotifier {
  @override
  Future<SeasonalMaps> build() async => SeasonalMaps(
    ranked: const [AppMap(id: '3', name: 'Olympus')],
    pubs: const [AppMap(id: '2', name: "World's Edge")],
  );
}

/// News that never arrives.
class _NoNews extends NewsNotifier {
  @override
  Future<ApiResult<List<NewsArticle>>> build() =>
      Completer<ApiResult<List<NewsArticle>>>().future;
}

void main() {
  late ProviderContainer container;

  Future<void> openHome(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    final (c, _) = await prefsContainer(
      values: prefs,
      overrides: [
        mapRotationProvider.overrideWith(
          (ref) async => ApiResult(
            MapRotation(
              battleRoyaleCurrent: _mode('Olympus'),
              battleRoyaleNext: _mode("World's Edge"),
              rankedCurrent: _mode('Kings Canyon'),
              rankedNext: _mode('Olympus'),
            ),
          ),
        ),
        // Left loading: a failed provider retries on a timer, which would
        // outlive the test.
        serverStatusProvider.overrideWith(
          (ref) => Completer<ApiResult<ServerStatus>>().future,
        ),
        newsProvider.overrideWith(_NoNews.new),
        seasonalMapsProvider.overrideWith(_Seasonal.new),
        predatorProvider.overrideWith(
          (ref) => Completer<ApiResult<PredatorResponse>>().future,
        ),
      ],
    );
    container = c;
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  // The map card's countdown timer ends with the widget, not the test.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  group('with no player set up', () {
    testWidgets('offers to set one up, and takes you to Stats', (
      tester,
    ) async {
      await openHome(tester);

      expect(find.text('Guest'), findsOneWidget);
      expect(find.text('Set up your player'), findsOneWidget);

      await tester.tap(find.text('Set up your player'));
      await tester.pump();

      expect(container.read(currentTabProvider), AppTab.stats);
      await close(tester);
    });

    testWidgets('puts the offer above the map', (tester) async {
      await openHome(tester);

      expect(
        tester.getTopLeft(find.text('Set up your player')).dy,
        lessThan(tester.getTopLeft(find.text('RANKED')).dy),
      );
      await close(tester);
    });
  });

  testWidgets('with a player set up, has no such offer', (tester) async {
    await openHome(tester, prefs: {PrefsKeys.playerName: 'Aceu'});

    expect(find.text('Aceu'), findsOneWidget);
    expect(find.text('Set up your player'), findsNothing);
    await close(tester);
  });

  group('the bell on the map card', () {
    testWidgets('turns on the alert for the mode on screen', (tester) async {
      await openHome(tester);
      expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_none_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final s = container.read(playerSettingsProvider);
      // Ranked is the mode first on screen; the others stay as they were.
      expect(s.notifyRankedMapRotation, isTrue);
      expect(s.rankedNotifyMinutesBefore, 15);
      expect(s.notifyPubsMapRotation, isFalse);
      expect(find.byIcon(Icons.notifications_active), findsOneWidget);
      await close(tester);
    });

    testWidgets('sets Pubs, not Ranked, once Pubs is on screen', (
      tester,
    ) async {
      await openHome(tester);

      await tester.tap(find.text('Pubs'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.notifications_none_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final s = container.read(playerSettingsProvider);
      expect(s.notifyPubsMapRotation, isTrue);
      expect(s.pubsNotifyMinutesBefore, 15);
      expect(s.notifyRankedMapRotation, isFalse);
      await close(tester);
    });

    testWidgets('keeps the lead time the mode already had', (tester) async {
      await openHome(tester);
      await container
          .read(playerSettingsProvider.notifier)
          .setRankedNotifyMinutesBefore(30);

      await tester.tap(find.byIcon(Icons.notifications_none_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(playerSettingsProvider).rankedNotifyMinutesBefore,
        30,
      );
      await close(tester);
    });

    testWidgets('opens the alerts sheet instead, once the alert is on', (
      tester,
    ) async {
      await openHome(tester);
      final settings = container.read(playerSettingsProvider.notifier);
      await settings.setRankedNotifyMinutesBefore(15);
      await settings.setNotifyRankedMapRotation(true);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.notifications_active));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Map Rotation Alerts'), findsOneWidget);
      // Opening the sheet changed nothing.
      expect(
        container.read(playerSettingsProvider).notifyRankedMapRotation,
        isTrue,
      );
      await close(tester);
    });
  });
}
