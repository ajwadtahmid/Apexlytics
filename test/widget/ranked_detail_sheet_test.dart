import 'dart:convert';

import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/entity_trend_overrides_provider.dart'
    show mapTrendKey;
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_legend_detail_sheet.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_map_detail_sheet.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/control_pill.dart';
import 'package:apexlytics/widgets/trend_window_picker.dart'
    show EntityTrendWindowPill;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers.dart';

void main() {
  RankedMatch game(int i) => buildMatch(start: 1000000 + i * 1000);

  final matches = [for (var i = 0; i < 12; i++) game(i)];

  final legend = (RankedAgg()..addAll(matches)).toLegend('Axle');
  final map = (RankedAgg()..addAll(matches)).toMap(
    'olympus_rotation',
    'Olympus',
  );

  Future<void> openSheet(
    WidgetTester tester,
    void Function(BuildContext) open, {
    Map<String, Object> saved = const {},
  }) async {
    SharedPreferences.setMockInitialValues(saved);
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

  group('the trend lines', () {
    // RP climbs a point a game, so the newest games are always above average.
    List<RankedMatch> climbing(int games) => [
      for (var i = 0; i < games; i++)
        buildMatch(
          start: 1000000 + i * 10000,
          rp: i + 1,
          kills: 2,
          damage: 300,
        ),
    ];

    Future<void> openLegend(
      WidgetTester tester,
      List<RankedMatch> games, {
      Map<String, Object> saved = const {},
    }) {
      final l = (RankedAgg()..addAll(games)).toLegend('Axle');
      return openSheet(
        tester,
        (context) =>
            showLegendDetailSheet(context, l, (_) async => games, () async {}),
        saved: saved,
      );
    }

    Future<void> openMap(
      WidgetTester tester,
      List<RankedMatch> games, {
      Map<String, Object> saved = const {},
    }) {
      final m = (RankedAgg()..addAll(games)).toMap(
        'olympus_rotation',
        'Olympus',
      );
      return openSheet(
        tester,
        (context) =>
            showMapDetailSheet(context, m, (_) async => games, () async {}),
        saved: saved,
      );
    }

    /// The pill's own label: its text is "N games".
    Finder pill(String label) => find.descendant(
      of: find.byType(ControlPill),
      matching: find.text(label),
    );

    testWidgets('say how recent play sits against the average above them', (
      tester,
    ) async {
      // 40 games: Auto's quarter is 10. RP 1..40: the newest ten average 35.5,
      // all forty 20.5.
      await openLegend(tester, climbing(40));

      expect(
        find.textContaining(
          'Avg RP +35.5 lately, 15.0 above your +20.5 average',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.text('Trends compare your last 10 games with your average.'),
        findsOneWidget,
      );
    });

    testWidgets('are in line with the average when recent games match it', (
      tester,
    ) async {
      await openLegend(tester, [
        for (var i = 0; i < 40; i++)
          buildMatch(start: 1000000 + i * 10000, rp: 10, kills: 2, damage: 300),
      ]);

      expect(
        find.textContaining(
          'Avg RP in line with your average',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Avg Kills in line with your average',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a legend with a lot of play looks at 100, no more', (
      tester,
    ) async {
      await openLegend(tester, climbing(1200));

      expect(find.textContaining('your last 100 games with'), findsOneWidget);
      expect(pill('100 games'), findsOneWidget);
    });

    testWidgets('a chosen count is used', (tester) async {
      await openLegend(tester, climbing(60), saved: {'entity_trend_games': 25});

      expect(find.textContaining('your last 25 games with'), findsOneWidget);
      expect(pill('25 games'), findsOneWidget);
    });

    testWidgets('a count too big for this legend is held to half its games', (
      tester,
    ) async {
      // 25 of 40 would be most of the history: half, 20, is the most.
      await openLegend(tester, climbing(40), saved: {'entity_trend_games': 25});

      expect(find.textContaining('your last 20 games with'), findsOneWidget);
      // And the pill says it was cut.
      expect(pill('20 games (max)'), findsOneWidget);
    });

    testWidgets('a count that fits is not marked as cut', (tester) async {
      await openLegend(tester, climbing(60), saved: {'entity_trend_games': 30});

      expect(pill('30 games'), findsOneWidget);
      expect(find.textContaining('(max)'), findsNothing);
    });

    testWidgets('Auto is never marked as cut', (tester) async {
      await openLegend(tester, climbing(12));

      expect(pill('5 games'), findsOneWidget);
    });

    testWidgets('too few games to compare: no lines, no footer, no pill', (
      tester,
    ) async {
      await openLegend(tester, climbing(9));

      expect(find.textContaining('lately', findRichText: true), findsNothing);
      expect(find.textContaining('Trends compare'), findsNothing);
      expect(find.byType(EntityTrendWindowPill), findsNothing);
    });

    testWidgets('a map has the same lines, footer and pill', (tester) async {
      await openMap(tester, climbing(40));

      expect(find.textContaining('lately', findRichText: true), findsWidgets);
      expect(find.textContaining('your last 10 games with'), findsOneWidget);
      expect(find.text('Trend window:'), findsOneWidget);
    });

    group("a legend's or map's own window", () {
      testWidgets('is offered on the pill, plain until one is set', (
        tester,
      ) async {
        await openLegend(tester, climbing(120));

        expect(find.text('Trend window:'), findsOneWidget);
        expect(pill('30 games'), findsOneWidget); // Auto: a quarter of 120
        final bg = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(ControlPill),
                matching: find.byType(Container),
              )
              .first,
        );
        expect((bg.decoration as BoxDecoration).color, AppTheme.surface2);
      });

      testWidgets('is chosen from a sheet named for the legend, and kept', (
        tester,
      ) async {
        await openLegend(tester, climbing(120));

        await tester.tap(pill('30 games'));
        await tester.pumpAndSettle();
        expect(find.text('Trend window for Axle'), findsOneWidget);
        expect(find.text('Default (Auto)'), findsOneWidget);
        // Half of 120 is 60, so 100 is not offered.
        for (final n in [10, 25, 50]) {
          expect(find.text('Last $n games'), findsOneWidget);
        }
        expect(find.text('Last 100 games'), findsNothing);
        await tester.tap(find.text('Last 50 games'));
        await tester.pumpAndSettle();

        // The sheet's lines now use it, and the pill is lit.
        expect(find.textContaining('your last 50 games with'), findsOneWidget);
        expect(pill('50 games'), findsOneWidget);
        final prefs = ProviderScope.containerOf(
          tester.element(find.byType(EntityTrendWindowPill)),
        ).read(sharedPreferencesProvider);
        expect(jsonDecode(prefs.getString('entity_trend_overrides')!), {
          'legend:Axle': 50,
        });
        final bg = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(ControlPill),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          (bg.decoration as BoxDecoration).color,
          isNot(AppTheme.surface2),
        );
      });

      testWidgets('leaves out the shortcuts it has too few games for', (
        tester,
      ) async {
        // 40 games: half, 20, is the most, so only 10 fits.
        await openLegend(tester, climbing(40));

        await tester.tap(pill('10 games'));
        await tester.pumpAndSettle();

        expect(find.text('Last 10 games'), findsOneWidget);
        for (final n in [25, 50, 100]) {
          expect(find.text('Last $n games'), findsNothing);
        }
        // Typing a count is still there, up to the same limit.
        expect(find.text('Custom…'), findsOneWidget);
      });

      testWidgets('Default takes it back to the window for everything', (
        tester,
      ) async {
        await openLegend(
          tester,
          climbing(120),
          saved: {
            'entity_trend_overrides': jsonEncode({'legend:Axle': 10}),
          },
        );
        expect(find.textContaining('your last 10 games with'), findsOneWidget);

        await tester.tap(pill('10 games'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Default (Auto)'));
        await tester.pumpAndSettle();

        expect(find.textContaining('your last 30 games with'), findsOneWidget);
        final prefs = ProviderScope.containerOf(
          tester.element(find.byType(EntityTrendWindowPill)),
        ).read(sharedPreferencesProvider);
        expect(prefs.containsKey('entity_trend_overrides'), isFalse);
      });

      testWidgets('leaves other legends alone', (tester) async {
        // Axle has its own window; the sheet opened is for Wraith.
        final games = climbing(120);
        final wraith = (RankedAgg()..addAll(games)).toLegend('Wraith');
        await openSheet(
          tester,
          (context) => showLegendDetailSheet(
            context,
            wraith,
            (_) async => games,
            () async {},
          ),
          saved: {
            'entity_trend_overrides': jsonEncode({'legend:Axle': 10}),
          },
        );

        expect(find.textContaining('your last 30 games with'), findsOneWidget);
      });

      testWidgets('can be Auto even when everything else is on a count', (
        tester,
      ) async {
        await openLegend(
          tester,
          climbing(120),
          saved: {'entity_trend_games': 100},
        );
        // 100 of 120 would be most of the history: half, 60, is the most.
        await tester.tap(pill('60 games (max)'));
        await tester.pumpAndSettle();
        expect(find.text('Default (100 games)'), findsOneWidget);
        expect(find.text('Auto'), findsOneWidget);

        await tester.tap(find.text('Auto'));
        await tester.pumpAndSettle();

        // Auto's quarter of 120.
        expect(find.textContaining('your last 30 games with'), findsOneWidget);
        expect(pill('30 games'), findsOneWidget);
        final prefs = ProviderScope.containerOf(
          tester.element(find.byType(EntityTrendWindowPill)),
        ).read(sharedPreferencesProvider);
        expect(jsonDecode(prefs.getString('entity_trend_overrides')!), {
          'legend:Axle': 0,
        });

        // Reopened, Auto is the one lit.
        await tester.tap(pill('30 games'));
        await tester.pumpAndSettle();
        final lit = tester.widget<Text>(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text('Auto'),
          ),
        );
        expect(lit.style?.color, AppTheme.accent);
      });

      group('a count typed in', () {
        Finder use() => find.widgetWithText(TextButton, 'Use');

        Future<void> openField(WidgetTester tester, String from) async {
          await tester.tap(pill(from));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Custom…'));
          await tester.pumpAndSettle();
        }

        Future<void> type(WidgetTester tester, String text) async {
          await tester.enterText(find.byType(TextField), text);
          await tester.pump();
        }

        testWidgets('can be at most half the legend\'s games, and says so', (
          tester,
        ) async {
          await openLegend(tester, climbing(120));
          await openField(tester, '30 games');

          expect(find.textContaining('5 to 60'), findsOneWidget);
          expect(find.text('Axle has 120 games, so up to 60.'), findsOneWidget);
        });

        testWidgets('is refused above that, and taken at it', (tester) async {
          await openLegend(tester, climbing(120));
          await openField(tester, '30 games');

          await type(tester, '61');
          expect(find.text('Enter 5 to 60'), findsOneWidget);
          expect(tester.widget<TextButton>(use()).onPressed, isNull);

          await type(tester, '60');
          expect(tester.widget<TextButton>(use()).onPressed, isNotNull);
          await tester.tap(use());
          await tester.pumpAndSettle();

          expect(pill('60 games'), findsOneWidget);
          expect(
            find.textContaining('your last 60 games with'),
            findsOneWidget,
          );
        });

        testWidgets('a legend with 500 games can go to 250', (tester) async {
          await openLegend(tester, climbing(500));
          await openField(tester, '100 games');

          expect(find.textContaining('5 to 250'), findsOneWidget);
          await type(tester, '251');
          expect(find.text('Enter 5 to 250'), findsOneWidget);
          await type(tester, '250');
          await tester.tap(use());
          await tester.pumpAndSettle();

          expect(pill('250 games'), findsOneWidget);
        });

        testWidgets('is kept for this legend alone, and lights the pill', (
          tester,
        ) async {
          await openLegend(tester, climbing(120));
          await openField(tester, '30 games');

          await type(tester, '40');
          await tester.tap(use());
          await tester.pumpAndSettle();

          final prefs = ProviderScope.containerOf(
            tester.element(find.byType(EntityTrendWindowPill)),
          ).read(sharedPreferencesProvider);
          expect(jsonDecode(prefs.getString('entity_trend_overrides')!), {
            'legend:Axle': 40,
          });
          expect(prefs.containsKey('entity_trend_games'), isFalse);
          final bg = tester.widget<Container>(
            find
                .descendant(
                  of: find.byType(ControlPill),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect(
            (bg.decoration as BoxDecoration).color,
            isNot(AppTheme.surface2),
          );

          // Reopened: the row shows what was typed, and is the lit one.
          await tester.tap(pill('40 games'));
          await tester.pumpAndSettle();
          final lit = tester.widget<Text>(find.text('Custom (40 games)'));
          expect(lit.style?.color, AppTheme.accent);
        });

        testWidgets('big numbers are written with a comma throughout', (
          tester,
        ) async {
          // 3,000 games: half is 1,500, so the most is the 1,000 limit.
          await openLegend(
            tester,
            climbing(3000),
            saved: {'entity_trend_games': 1000},
          );

          expect(pill('1,000 games'), findsOneWidget);
          expect(
            find.text(
              'Trends compare your last 1,000 games with your average.',
            ),
            findsOneWidget,
          );

          await tester.tap(pill('1,000 games'));
          await tester.pumpAndSettle();
          // Chosen for everything, so on its own sheet the row is still "Custom…".
          await tester.tap(find.text('Custom…'));
          await tester.pumpAndSettle();

          expect(
            find.text('Axle has 3,000 games, so up to 1,000.'),
            findsOneWidget,
          );
          expect(find.textContaining('5 to 1,000'), findsOneWidget);
          expect(find.textContaining('1000'), findsNothing);
        });

        testWidgets('a map can have one too', (tester) async {
          await openMap(tester, climbing(120));
          await openField(tester, '30 games');

          expect(
            find.text('Olympus has 120 games, so up to 60.'),
            findsOneWidget,
          );
          await type(tester, '45');
          await tester.tap(use());
          await tester.pumpAndSettle();

          expect(pill('45 games'), findsOneWidget);
        });
      });

      testWidgets('has no second Auto row when Auto is already the default', (
        tester,
      ) async {
        await openLegend(tester, climbing(120));

        await tester.tap(pill('30 games'));
        await tester.pumpAndSettle();

        expect(find.text('Default (Auto)'), findsOneWidget);
        expect(find.text('Auto'), findsNothing);
      });

      testWidgets('the pill sits at the left', (tester) async {
        await openLegend(tester, climbing(120));

        final pillLeft = tester.getTopLeft(find.byType(EntityTrendWindowPill));
        final sheetCentre = tester.getCenter(find.byType(BottomSheet));
        expect(pillLeft.dx, lessThan(sheetCentre.dx - 100));
      });

      testWidgets('is not lit when it matches what everything else uses', (
        tester,
      ) async {
        await openLegend(
          tester,
          climbing(120),
          saved: {
            'entity_trend_games': 25,
            'entity_trend_overrides': jsonEncode({'legend:Axle': 25}),
          },
        );

        final bg = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(ControlPill),
                matching: find.byType(Container),
              )
              .first,
        );
        expect((bg.decoration as BoxDecoration).color, AppTheme.surface2);
      });

      testWidgets('follows the window chosen for everything when it has none', (
        tester,
      ) async {
        await openLegend(
          tester,
          climbing(120),
          saved: {'entity_trend_games': 50},
        );

        expect(find.textContaining('your last 50 games with'), findsOneWidget);
        await tester.tap(pill('50 games'));
        await tester.pumpAndSettle();
        expect(find.text('Default (50 games)'), findsOneWidget);
      });

      testWidgets('a map can have one too, filed apart from legends', (
        tester,
      ) async {
        await openMap(tester, climbing(120));

        await tester.tap(pill('30 games'));
        await tester.pumpAndSettle();
        expect(find.text('Trend window for Olympus'), findsOneWidget);
        await tester.tap(find.text('Last 50 games'));
        await tester.pumpAndSettle();

        expect(pill('50 games'), findsOneWidget);
        final prefs = ProviderScope.containerOf(
          tester.element(find.byType(EntityTrendWindowPill)),
        ).read(sharedPreferencesProvider);
        expect(jsonDecode(prefs.getString('entity_trend_overrides')!), {
          mapTrendKey('olympus_rotation'): 50,
        });
      });
    });
  });
}
