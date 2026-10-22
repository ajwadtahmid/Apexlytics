import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/best_metric_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/utils/ranked/best_metric.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/best_metric_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Map<String, Object> saved = const {},
  }) async {
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: BestMetricPill())),
        ),
      ),
    );
    return container;
  }

  testWidgets('the pill says what is chosen, Total RP until changed', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Rank by:'), findsOneWidget);
    expect(find.text('Total RP'), findsOneWidget);

    await pump(tester, saved: {PrefsKeys.bestMetric: 'totalDamage'});
    expect(find.text('Total Damage'), findsOneWidget);
  });

  testWidgets('tapping it lists every measure in order, with an icon each', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Total RP'));
    await tester.pumpAndSettle();

    expect(find.text('Rank legends and maps by'), findsOneWidget);
    // Down the sheet in the order the measures are listed.
    final names = [for (final m in BestMetric.values) m.label];
    expect(names, [
      'Total RP',
      'Avg RP',
      'Win rate',
      'Avg Kills',
      'Total Kills',
      'Avg Damage',
      'Total Damage',
    ]);
    double top(String label) => tester.getTopLeft(find.text(label).last).dy;
    expect([...names]..sort((a, b) => top(a).compareTo(top(b))), names);
    // The icons of the list, as well as the pill's: each is the one its
    // figure wears across the app, and no two of them are alike.
    final icons = [for (final m in BestMetric.values) bestMetricIcon(m)];
    expect(icons.toSet().length, icons.length);
    for (final icon in icons) {
      expect(find.byIcon(icon), findsWidgets, reason: '$icon');
    }
    expect(find.textContaining('3 or more'), findsOneWidget);
  });

  testWidgets('has no line under the title, nor under the chosen one', (
    tester,
  ) async {
    await pump(tester, saved: {PrefsKeys.bestMetric: 'totalKills'});

    await tester.tap(find.text('Total Kills'));
    await tester.pumpAndSettle();

    expect(find.text('Decides which are strongest and weakest.'), findsNothing);
    expect(find.text('All the kills added up'), findsNothing);
    // One list tile each and nothing under their names.
    expect(find.byType(ListTile), findsNWidgets(BestMetric.values.length));
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
      expect(tile.subtitle, isNull);
    }
  });

  testWidgets('only the one in use is lit, with a tick', (tester) async {
    await pump(tester, saved: {PrefsKeys.bestMetric: 'totalKills'});

    await tester.tap(find.text('Total Kills'));
    await tester.pumpAndSettle();

    final tick = tester.widget<Icon>(find.byIcon(Icons.check));
    expect(tick.color, AppTheme.accent);
    expect(find.byIcon(Icons.check), findsOneWidget);
    final lit = tester.widget<Text>(find.text('Total Kills').last);
    expect(lit.style?.color, AppTheme.accent);
    final other = tester.widget<Text>(find.text('Avg Kills'));
    expect(other.style?.color, isNot(AppTheme.accent));
  });

  testWidgets('choosing one changes it everywhere, keeps it, and closes', (
    tester,
  ) async {
    final container = await pump(tester);

    await tester.tap(find.text('Total RP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Total Kills'));
    await tester.pumpAndSettle();

    expect(container.read(bestMetricProvider), BestMetric.totalKills);
    expect(
      container.read(sharedPreferencesProvider).getString(PrefsKeys.bestMetric),
      'totalKills',
    );
    // The sheet is gone and the pill reads the new choice.
    expect(find.text('Rank legends and maps by'), findsNothing);
    expect(find.text('Total Kills'), findsOneWidget);
    expect(find.text('Total RP'), findsNothing);
  });
}
