import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_entity_history_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_pick_rate_screen.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

List<RankedMatch> _games(String legend, int n, int rp) => [
  for (var i = 0; i < n; i++)
    buildMatch(
      legend: legend,
      rp: rp,
      start: 1782090000 + legend.hashCode % 1000 + i * 5000,
    ),
];

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<RankedMatch> matches, {
    Future<List<RankedMatch>> Function(String legend)? matchesFor,
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: RankedPickRateScreen(
            summary: summarize(matches),
            legends: legendBreakdowns(matches),
            matchesFor: matchesFor,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ScatterChartData chart(WidgetTester tester) =>
      tester.widget<ScatterChart>(find.byType(ScatterChart)).data;

  // Alter is half the games and loses RP; Bangalore is played less and wins.
  final matches = [
    ..._games('Alter', 8, -5),
    ..._games('Bangalore', 4, 20),
    ..._games('Wraith', 4, -3),
  ];

  testWidgets(
    'says which legend is the comfort trap and which the hidden gem',
    (tester) async {
      await pump(tester, matches);

      expect(find.textContaining('Alter', findRichText: true), findsOneWidget);
      expect(find.textContaining('Comfort trap'), findsWidgets);
      expect(
        find.text('50% of your games at -5.0 RP per game'),
        findsOneWidget,
      );
      expect(find.textContaining('Hidden gem'), findsWidgets);
      expect(
        find.text('25% of your games at +20.0 RP per game'),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping one selects that legend on the chart', (tester) async {
    await pump(tester, matches);
    expect(find.text('Tap a legend to see details'), findsOneWidget);

    await tester.tap(find.text('50% of your games at -5.0 RP per game'));
    await tester.pump();

    expect(find.text('Tap a legend to see details'), findsNothing);
    expect(find.textContaining('50.0% pick rate'), findsOneWidget);
  });

  testWidgets('says nothing when no legend is a trap or a gem', (tester) async {
    await pump(tester, _games('Alter', 8, 5));

    expect(find.textContaining('Comfort trap  '), findsNothing);
    expect(find.textContaining('of your games at'), findsNothing);
    expect(find.byType(ScatterChart), findsOneWidget);
  });

  testWidgets('explains the dashed lines and labels the axes', (tester) async {
    await pump(tester, matches);

    expect(
      find.text(
        'Dashed lines: an even share of games (33%) and 0 RP per game.',
      ),
      findsOneWidget,
    );
    expect(find.text('Share of your games'), findsOneWidget);
    expect(find.text('Avg RP per game'), findsOneWidget);
  });

  group('the axes', () {
    test('step to round numbers', () {
      expect(niceAxisStep(614, ticks: 8), 100);
      expect(niceAxisStep(80, ticks: 6), 20);
      expect(niceAxisStep(24, ticks: 8), 5);
      expect(niceAxisStep(1, ticks: 8), 0.2);
    });

    testWidgets('end on a labelled tick, even with a very wide RP range', (
      tester,
    ) async {
      await pump(tester, [
        ..._games('Alter', 30, 4),
        ..._games('Bangalore', 3, 307),
        ..._games('Wraith', 3, -150),
      ]);

      final data = chart(tester);
      final yStep = data.titlesData.leftTitles.sideTitles.interval!;
      final xStep = data.titlesData.bottomTitles.sideTitles.interval!;
      expect(data.maxY % yStep, 0);
      expect(data.minY, -data.maxY);
      expect(data.maxX % xStep, 0);
      // The widest dot is on the chart, and not by a lot.
      expect(data.maxY, greaterThanOrEqualTo(307));
      expect(data.maxY, lessThan(307 * 2));
    });
  });

  group('opening a legend\'s history', () {
    Future<List<RankedMatch>> lookup(String legend) async => [
      for (final m in matches)
        if (m.legend == legend) m,
    ];

    testWidgets('tapping the selected legend opens its matches', (
      tester,
    ) async {
      final asked = <String>[];
      await pump(
        tester,
        matches,
        matchesFor: (legend) {
          asked.add(legend);
          return lookup(legend);
        },
      );
      await tester.tap(find.text('50% of your games at -5.0 RP per game'));
      await tester.pump();

      await tester.tap(find.textContaining('50.0% pick rate'));
      await tester.pumpAndSettle();

      expect(asked, ['Alter']);
      expect(find.byType(RankedEntityHistoryScreen), findsOneWidget);
      expect(find.text('Alter'), findsWidgets);
    });

    testWidgets('has no link when there is nowhere to go', (tester) async {
      await pump(tester, matches);
      await tester.tap(find.text('50% of your games at -5.0 RP per game'));
      await tester.pump();

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      await tester.tap(find.textContaining('50.0% pick rate'));
      await tester.pumpAndSettle();
      expect(find.byType(RankedEntityHistoryScreen), findsNothing);
    });

    testWidgets('shows a chevron on the card when it opens something', (
      tester,
    ) async {
      await pump(tester, matches, matchesFor: lookup);
      await tester.tap(find.text('50% of your games at -5.0 RP per game'));
      await tester.pump();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });
}
