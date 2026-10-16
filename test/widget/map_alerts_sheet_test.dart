import 'package:apexlytics/constants/map_constants.dart';
import 'package:apexlytics/models/seasonal_maps.dart';
import 'package:apexlytics/providers/map_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/settings/map_alerts_sheet.dart';
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
    required List<String> rankedFavourites,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        seasonalMapsProvider.overrideWith(_FakeSeasonalMaps.new),
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
}
