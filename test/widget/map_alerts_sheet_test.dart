import 'dart:async';

import 'package:apexlytics/constants/map_constants.dart';
import 'package:apexlytics/models/seasonal_maps.dart';
import 'package:apexlytics/providers/map_provider.dart';
import 'package:apexlytics/providers/notification_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/settings/map_alerts_sheet.dart';
import 'package:apexlytics/services/notification_service.dart' show TestAlertResult;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The season's map pool, without asking the server for it.
class _FakeSeasonalMaps extends SeasonalMapsNotifier {
  @override
  Future<SeasonalMaps> build() async => SeasonalMaps(
    ranked: const [
      AppMap(id: '2', name: "World's Edge"),
      AppMap(id: '3', name: 'Olympus'),
    ],
    pubs: const [AppMap(id: '2', name: "World's Edge")],
  );
}

void main() {
  late ProviderContainer container;

  Future<void> openSheet(
    WidgetTester tester, {
    List<String> rankedFavourites = const [],
    Future<TestAlertResult> Function()? sendTest,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        seasonalMapsProvider.overrideWith(_FakeSeasonalMaps.new),
        if (sendTest != null) testAlertSenderProvider.overrideWithValue(sendTest),
        // A reschedule asks for the rotation; nothing should leave the test.
        mapRotationProvider.overrideWith(
          (ref) async => throw Exception('no network in tests'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final settings = container.read(playerSettingsProvider.notifier);
    await settings.setRankedNotifyMinutesBefore(15);
    await settings.setNotifyRankedMapRotation(true);
    await settings.setFavoriteRankedMapNames(rankedFavourites);

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMapAlertsSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('unticking the last Ranked map turns Ranked alerts off, not on '
      'for every map', (tester) async {
    // An empty favourites list means "every map".
    await openSheet(tester, rankedFavourites: ['Olympus']);

    await tester.tap(find.text('Olympus'));
    await tester.pumpAndSettle();

    final settings = container.read(playerSettingsProvider);
    expect(settings.notifyRankedMapRotation, isFalse);
    // Stored as "all maps", so re-enabling shows every map ticked.
    expect(settings.favoriteRankedMapNames, isEmpty);
    expect(find.textContaining('Ranked alerts are off'), findsOneWidget);
  });

  testWidgets('unticking a map while others stay ticked changes nothing else', (
    tester,
  ) async {
    await openSheet(tester, rankedFavourites: ['Olympus', "World's Edge"]);

    await tester.tap(find.text('Olympus'));
    await tester.pumpAndSettle();

    final settings = container.read(playerSettingsProvider);
    expect(settings.notifyRankedMapRotation, isTrue);
    expect(settings.favoriteRankedMapNames, ["World's Edge"]);
    expect(find.textContaining('alerts are off'), findsNothing);
  });
  group('Send a test alert', () {
    Finder button() => find.text('Send a test alert');

    testWidgets('sends one and says when', (tester) async {
      var sent = 0;
      await openSheet(
        tester,
        sendTest: () async {
          sent++;
          return TestAlertResult.sent;
        },
      );
      expect(find.textContaining('Sent at'), findsNothing);

      await tester.tap(button());
      await tester.pumpAndSettle();

      expect(sent, 1);
      expect(
        find.textContaining(RegExp(r'^Sent at \d{1,2}:\d{2} [AP]M\.')),
        findsOneWidget,
      );
    });

    testWidgets('can be sent again', (tester) async {
      var sent = 0;
      await openSheet(
        tester,
        sendTest: () async {
          sent++;
          return TestAlertResult.sent;
        },
      );

      await tester.tap(button());
      await tester.pumpAndSettle();
      await tester.tap(button());
      await tester.pumpAndSettle();
      await tester.tap(button());
      await tester.pumpAndSettle();

      expect(sent, 3);
      expect(find.textContaining('Sent at'), findsOneWidget);
    });

    testWidgets('waits for the one in flight', (tester) async {
      final done = Completer<TestAlertResult>();
      var sent = 0;
      await openSheet(
        tester,
        sendTest: () {
          sent++;
          return done.future;
        },
      );

      await tester.tap(button());
      await tester.pump();
      await tester.tap(button());
      await tester.pump();
      expect(sent, 1);

      done.complete(TestAlertResult.sent);
      await tester.pumpAndSettle();
      await tester.tap(button());
      await tester.pumpAndSettle();
      expect(sent, 2);
    });

    testWidgets('says when notifications are off, and offers the fix', (
      tester,
    ) async {
      await openSheet(
        tester,
        sendTest: () async => TestAlertResult.permissionOff,
      );

      await tester.tap(button());
      await tester.pumpAndSettle();

      expect(find.text('Notifications are off for Apexlytics.'), findsOneWidget);
      expect(find.text('Fix'), findsOneWidget);
    });

    testWidgets('says when alerts could not start or could not be sent', (
      tester,
    ) async {
      var result = TestAlertResult.notReady;
      await openSheet(tester, sendTest: () async => result);

      await tester.tap(button());
      await tester.pumpAndSettle();
      expect(
        find.text("Alerts couldn't start. Try restarting the app."),
        findsOneWidget,
      );

      result = TestAlertResult.failed;
      await tester.tap(button());
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't send"), findsOneWidget);
      expect(
        find.text("Alerts couldn't start. Try restarting the app."),
        findsNothing,
      );
    });

    testWidgets('works with every alert off', (tester) async {
      await openSheet(tester, sendTest: () async => TestAlertResult.sent);
      final settings = container.read(playerSettingsProvider.notifier);
      await settings.setNotifyRankedMapRotation(false);
      await tester.pumpAndSettle();

      await tester.tap(button());
      await tester.pumpAndSettle();

      expect(find.textContaining('Sent at'), findsOneWidget);
    });
  });
}
