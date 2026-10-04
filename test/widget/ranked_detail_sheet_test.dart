import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_legend_detail_sheet.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_map_detail_sheet.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  RankedMatch game(int i) => RankedMatch.fromJson({
    'uid': '1',
    'name': 'Tester',
    'legendPlayed': 'Axle',
    'gameMode': 'BATTLE_ROYALE',
    'gameLengthSecs': 600,
    'gameStartTimestamp': 1000000 + i * 1000,
    'gameEndTimestamp': 1000600 + i * 1000,
    'gameData': const [],
    'BRScoreChange': 10,
    'BRScore': 1000,
    'map': 'olympus_rotation',
  });

  final matches = [for (var i = 0; i < 12; i++) game(i)];

  final legend = (RankedAgg()..addAll(matches)).toLegend('Axle');
  final map = (RankedAgg()..addAll(matches)).toMap('olympus_rotation', 'Olympus');

  Future<void> openSheet(
    WidgetTester tester,
    void Function(BuildContext) open,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // A window resize changes MediaQuery, which rebuilds the sheet.
  Future<void> resize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
  }

  testWidgets('the map sheet loads its matches once, not per rebuild', (
    tester,
  ) async {
    var loads = 0;
    await openSheet(
      tester,
      (context) => showMapDetailSheet(context, map, (_) async {
        loads++;
        return matches;
      }, () async {}),
    );
    expect(loads, 1);

    await resize(tester);
    await resize(tester);

    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the legend sheet loads its matches once, not per rebuild', (
    tester,
  ) async {
    var loads = 0;
    await openSheet(
      tester,
      (context) => showLegendDetailSheet(context, legend, (_) async {
        loads++;
        return matches;
      }, () async {}),
    );
    expect(loads, 1);

    await resize(tester);

    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });
}
