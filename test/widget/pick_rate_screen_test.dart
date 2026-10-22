import 'package:apexlytics/constants/prefs_keys.dart';
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
    Map<String, Object> saved = const {},
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(saved);
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
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('Pick rate'), findsOneWidget);
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

      await tester.tap(find.text('Pick rate'));
      await tester.pumpAndSettle();

      // Once for the card's map lines, again for the history it opens.
      expect(asked, ['Alter', 'Alter']);
      expect(find.byType(RankedEntityHistoryScreen), findsOneWidget);
      expect(find.text('Alter'), findsWidgets);
    });

    testWidgets('has no link when there is nowhere to go', (tester) async {
      await pump(tester, matches);
      await tester.tap(find.text('50% of your games at -5.0 RP per game'));
      await tester.pump();

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      await tester.tap(find.text('Pick rate'));
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

  group('the selected legend\'s card', () {
    // Alone, Alter is a comfort trap: 4 games on Olympus (+10 each) and 4 on
    // Kings Canyon (-20 each).
    final alter = [
      for (var i = 0; i < 4; i++)
        buildMatch(
          legend: 'Alter',
          rp: 10,
          kills: 2,
          damage: 400,
          map: 'olympus_rotation',
          start: 1782090000 + i * 5000,
        ),
      for (var i = 0; i < 4; i++)
        buildMatch(
          legend: 'Alter',
          rp: -20,
          kills: 4,
          damage: 800,
          map: 'kings_canyon_rotation',
          start: 1782190000 + i * 5000,
        ),
    ];

    Future<List<RankedMatch>> lookup(String legend) async => [
      for (final m in alter)
        if (m.legend == legend) m,
    ];

    Future<void> selectAlter(WidgetTester tester) async {
      await tester.tap(find.textContaining('of your games at'));
      await tester.pump();
    }

    testWidgets('shows pick rate, win rate, kills and damage', (tester) async {
      await pump(tester, alter);
      await selectAlter(tester);

      expect(find.text('8 games'), findsOneWidget);
      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('3.0'), findsOneWidget);
      expect(find.text('600'), findsOneWidget);
      expect(find.text('Kills'), findsOneWidget);
      expect(find.text('Damage'), findsOneWidget);
    });

    testWidgets('shows the best and worst map once they load', (tester) async {
      await pump(tester, alter, matchesFor: lookup);
      await selectAlter(tester);
      await tester.pump();

      // By total RP, the default: four games at +10, and four at -20.
      expect(find.text('Best'), findsOneWidget);
      expect(find.text('Olympus'), findsOneWidget);
      expect(
        find.textContaining('+40 RP · 4 games', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Worst'), findsOneWidget);
      expect(find.text('Kings Canyon'), findsOneWidget);
      expect(
        find.textContaining('-80 RP · 4 games', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('writes them by the measure chosen', (tester) async {
      await pump(
        tester,
        alter,
        matchesFor: lookup,
        saved: {'best_metric': 'avgRp'},
      );
      await selectAlter(tester);
      await tester.pump();

      expect(
        find.textContaining('+10.0 RP/game · 4 games', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('-20.0 RP/game · 4 games', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('has no map lines where nothing can be looked up', (
      tester,
    ) async {
      await pump(tester, alter);
      await selectAlter(tester);
      await tester.pump();

      expect(find.text('Best'), findsNothing);
      expect(find.text('Worst'), findsNothing);
    });

    testWidgets('looks a legend up only once', (tester) async {
      final asked = <String>[];
      await pump(
        tester,
        alter,
        matchesFor: (legend) {
          asked.add(legend);
          return lookup(legend);
        },
      );
      await selectAlter(tester);
      await tester.pump();
      await selectAlter(tester);
      await tester.pump();

      expect(asked, ['Alter']);
    });
  });

  group('the table', () {
    // Alter 8 games at -5, Bangalore 4 at +20, Wraith 4 at -3.
    Future<void> openTable(
      WidgetTester tester, {
      Future<List<RankedMatch>> Function(String legend)? matchesFor,
    }) async {
      await pump(tester, matches, matchesFor: matchesFor);
      await tester.tap(find.text('Table'));
      await tester.pump();
    }

    List<String> rowOrder(WidgetTester tester) {
      final names = ['Alter', 'Bangalore', 'Wraith'];
      final found = [
        for (final n in names) (n, tester.getTopLeft(find.text(n).first).dy),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      return [for (final f in found) f.$1];
    }

    testWidgets('lists every legend with its figures, most played first', (
      tester,
    ) async {
      await openTable(tester);

      expect(rowOrder(tester), ['Alter', 'Bangalore', 'Wraith']);
      for (final h in [
        'LEGEND',
        'PICK',
        'WIN',
        'RP/G',
        'NET',
        'KILLS',
        'DMG',
      ]) {
        expect(find.text(h), findsOneWidget);
      }
      expect(find.text('8 games'), findsOneWidget);
      expect(find.text('+20.0'), findsOneWidget);
      expect(find.text('+80'), findsOneWidget);
      expect(find.text('-40'), findsOneWidget);
    });

    testWidgets('a heading sorts by it, and again turns it round', (
      tester,
    ) async {
      await openTable(tester);

      await tester.tap(find.text('RP/G'));
      await tester.pump();
      expect(rowOrder(tester), ['Bangalore', 'Wraith', 'Alter']);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

      await tester.tap(find.text('RP/G'));
      await tester.pump();
      expect(rowOrder(tester), ['Alter', 'Wraith', 'Bangalore']);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('no two headings overlap, whichever one is sorted', (
      tester,
    ) async {
      await openTable(tester);
      tester.view.physicalSize = const Size(360, 800);
      await tester.pump();
      const headings = ['LEGEND', 'PICK', 'WIN', 'RP/G', 'NET', 'KILLS', 'DMG'];

      for (final sorted in headings) {
        await tester.tap(find.text(sorted));
        await tester.pump();
        final rects = [for (final h in headings) tester.getRect(find.text(h))];
        // The sort arrow is part of its heading.
        final at = headings.indexOf(sorted);
        rects[at] = rects[at].expandToInclude(
          tester.getRect(
            find.descendant(
              of: find.ancestor(
                of: find.text(sorted),
                matching: find.byType(InkWell),
              ),
              matching: find.byType(Icon),
            ),
          ),
        );
        for (var i = 0; i < rects.length - 1; i++) {
          expect(
            rects[i + 1].left - rects[i].right,
            greaterThanOrEqualTo(2),
            reason:
                '${headings[i]} runs into ${headings[i + 1]} '
                'when sorted by $sorted',
          );
        }
      }
    });

    testWidgets('the legend heading sorts A to Z first', (tester) async {
      await openTable(tester);

      await tester.tap(find.text('PICK'));
      await tester.pump();
      await tester.tap(find.text('LEGEND'));
      await tester.pump();

      expect(rowOrder(tester), ['Alter', 'Bangalore', 'Wraith']);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('tapping a row shows that legend\'s card below', (
      tester,
    ) async {
      await openTable(tester);
      expect(find.text('Best'), findsNothing);
      expect(find.text('Pick rate'), findsNothing);

      await tester.tap(find.text('Bangalore'));
      await tester.pump();

      expect(find.text('Pick rate'), findsOneWidget);
      expect(find.text('25.0%'), findsWidgets);
    });

    testWidgets('the selection is the one the chart shows', (tester) async {
      await openTable(tester);
      await tester.tap(find.text('Bangalore'));
      await tester.pump();

      await tester.tap(find.text('Chart'));
      await tester.pump();

      expect(find.text('Pick rate'), findsOneWidget);
      expect(find.text('Tap a legend to see details'), findsNothing);
    });
  });

  group('Customize', () {
    // Alter sits just above 0 RP, so it is a core legend against 0 but below
    // the player's average of +4.8. Zed has too few games to show.
    final custom = [
      ..._games('Alter', 8, 1),
      ..._games('Bangalore', 4, 20),
      ..._games('Wraith', 4, -3),
      ..._games('Zed', 2, 5),
    ];

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Customize'));
      await tester.pumpAndSettle();
    }

    testWidgets('says what each choice does, with the counts', (tester) async {
      await pump(tester, custom);
      await openSheet(tester);

      expect(find.text('Legends shown'), findsOneWidget);
      expect(find.text('3+ games'), findsOneWidget);
      expect(
        find.text(
          'Showing 3 of 4. Hiding 1 legend with under 3 games: too few for '
          'a steady average.',
        ),
        findsOneWidget,
      );
      expect(find.text('Good means'), findsOneWidget);
      expect(
        find.text(
          'The dashed line sits at 0 RP per game. Your average is +4.8 RP '
          'per game; using it would move 1 legend.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('says nothing is hidden when every legend qualifies', (
      tester,
    ) async {
      await pump(tester, matches);
      await openSheet(tester);

      expect(
        find.text(
          "Every legend you've played has at least 3 games, so none are "
          'hidden.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('All adds the legends with few games, and is kept', (
      tester,
    ) async {
      await pump(tester, custom);
      expect(chart(tester).scatterSpots, hasLength(3));
      await openSheet(tester);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Including 1 legend with under 3 games. Their averages can swing a '
          'lot.',
        ),
        findsOneWidget,
      );
      expect(chart(tester).scatterSpots, hasLength(4));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.pickRateShowAll), isTrue);
    });

    testWidgets('Above my average moves the line and is kept', (tester) async {
      await pump(tester, custom);
      expect(find.textContaining('and 0 RP per game'), findsOneWidget);
      await openSheet(tester);

      await tester.tap(find.text('Above my average'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The dashed line sits at your average, +4.8 RP per game. Using 0 RP '
          'instead would move 1 legend.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('your average of +4.8 RP'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.pickRateOwnAverage), isTrue);
    });

    testWidgets('says no legend would move when none sit between the lines', (
      tester,
    ) async {
      await pump(tester, matches);
      await openSheet(tester);

      expect(find.textContaining("wouldn't move any legend"), findsOneWidget);
    });

    testWidgets('starts as it was left', (tester) async {
      await pump(
        tester,
        custom,
        saved: {
          PrefsKeys.pickRateShowAll: true,
          PrefsKeys.pickRateOwnAverage: true,
        },
      );

      expect(chart(tester).scatterSpots, hasLength(4));
      expect(find.textContaining('your average of +4.8 RP'), findsOneWidget);
    });

    testWidgets('changing what is shown clears the selected legend', (
      tester,
    ) async {
      await pump(tester, custom);
      await tester.tap(find.textContaining('of your games at'));
      await tester.pump();
      expect(find.text('Tap a legend to see details'), findsNothing);

      await openSheet(tester);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      // The sheet is still over the page; close it to look.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Tap a legend to see details'), findsOneWidget);
    });
  });

  group('the view selector and info', () {
    testWidgets('a Chart | Table selector sits on the page, not the app bar', (
      tester,
    ) async {
      await pump(tester, matches);

      expect(find.text('Chart'), findsOneWidget);
      expect(find.text('Table'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.table_rows_outlined),
        ),
        findsNothing,
      );
      expect(find.byType(ScatterChart), findsOneWidget);
    });

    testWidgets(
      'picking Table shows the table, and Chart brings the chart back',
      (tester) async {
        await pump(tester, matches);

        await tester.tap(find.text('Table'));
        await tester.pump();
        expect(find.byType(ScatterChart), findsNothing);
        expect(find.text('LEGEND'), findsOneWidget);

        await tester.tap(find.text('Chart'));
        await tester.pump();
        expect(find.byType(ScatterChart), findsOneWidget);
        expect(find.text('LEGEND'), findsNothing);
      },
    );

    testWidgets('the choice is kept', (tester) async {
      await pump(tester, matches);
      await tester.tap(find.text('Table'));
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.pickRateTable), isTrue);
    });

    testWidgets('opens on the table when it was left there', (tester) async {
      await pump(tester, matches, saved: {PrefsKeys.pickRateTable: true});

      expect(find.byType(ScatterChart), findsNothing);
      expect(find.text('LEGEND'), findsOneWidget);
    });

    testWidgets('has no selector when there is nothing to show', (
      tester,
    ) async {
      await pump(tester, const []);

      expect(find.text('Chart'), findsNothing);
      expect(find.text('Table'), findsNothing);
    });

    testWidgets('the info button explains how to read the page', (
      tester,
    ) async {
      await pump(tester, matches);

      await tester.tap(find.byTooltip('How to read this'));
      await tester.pumpAndSettle();

      expect(find.text('Pick Rate'), findsWidgets);
      expect(find.textContaining('Each dot is a legend'), findsOneWidget);
      expect(find.textContaining('hidden gem'), findsOneWidget);
      expect(find.textContaining('choose All in Customize'), findsOneWidget);
    });

    testWidgets('the app bar has Customize, then info', (tester) async {
      await pump(tester, matches);

      final tune = tester.getCenter(find.byIcon(Icons.tune));
      final info = tester.getCenter(find.byIcon(Icons.info_outline));
      expect(info.dx, greaterThan(tune.dx));
    });
  });
}
