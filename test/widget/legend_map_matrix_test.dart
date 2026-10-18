import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/map_rotation.dart';
import 'package:apexlytics/providers/map_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_entity_history_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_legend_map_matrix_screen.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/widgets/legend_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

MapMode _mode(String map) =>
    MapMode(map: map, remainingSecs: 600, durationMins: 60, asset: '');

MapRotation _rotation(String rankedNow) => MapRotation(
  battleRoyaleCurrent: _mode('Olympus'),
  battleRoyaleNext: _mode('Olympus'),
  rankedCurrent: _mode(rankedNow),
  rankedNext: _mode('Olympus'),
);

/// [n] games of [legend] on [map] netting [rp] each.
List<RankedMatch> _games(String legend, String map, int n, int rp, int seed) =>
    [
      for (var i = 0; i < n; i++)
        buildMatch(
          legend: legend,
          map: map,
          rp: rp,
          start: 1782090000 + (seed + i) * 5000,
        ),
    ];

void main() {
  group('mapLegendInsights', () {
    final cells = legendMapBreakdowns([
      ..._games('Bangalore', 'olympus_rotation', 4, 30, 0),
      ..._games('Axle', 'olympus_rotation', 6, 10, 10),
      ..._games('Wraith', 'olympus_rotation', 2, 90, 20), // too few games
      ..._games('Axle', 'storm_point_rotation', 2, 50, 30),
    ]);
    final byMap = {for (final i in mapLegendInsights(cells)) i.mapName: i};

    test('most-played map first, with its record', () {
      final all = mapLegendInsights(cells);
      expect(all.first.mapName, 'Olympus');
      expect(all.first.games, 12);
      expect(all.first.totalRp, 4 * 30 + 6 * 10 + 2 * 90);
    });

    test('the best legend needs enough games on that map', () {
      expect(byMap['Olympus']!.best!.legend, 'Bangalore');
      expect(byMap['Storm Point']!.best, isNull);
      expect(byMap['Storm Point']!.hasRecord, isFalse);
    });

    test('the worst legend is the lowest of those with enough games', () {
      expect(byMap['Olympus']!.worst!.legend, 'Axle');
      expect(byMap['Olympus']!.qualified, 2);
    });

    test('there is no worst with fewer than two legends to compare', () {
      expect(byMap['Storm Point']!.worst, isNull);
      expect(byMap['Storm Point']!.qualified, 0);
      final one = mapLegendInsights(
        legendMapBreakdowns(_games('Axle', 'olympus_rotation', 5, 10, 0)),
      );
      expect(one.single.best!.legend, 'Axle');
      expect(one.single.worst, isNull);
      expect(one.single.qualified, 1);
    });

    test('equal legends have no worst, as it would not be worse', () {
      final level = mapLegendInsights(
        legendMapBreakdowns([
          ..._games('Axle', 'olympus_rotation', 3, 20, 0),
          ..._games('Bangalore', 'olympus_rotation', 5, 20, 10),
        ]),
      );
      expect(level.single.best!.legend, 'Bangalore');
      expect(level.single.worst, isNull);
    });

    test('a tie on RP per game goes to the legend with more games', () {
      final tie = mapLegendInsights(
        legendMapBreakdowns([
          ..._games('Axle', 'olympus_rotation', 3, 20, 0),
          ..._games('Bangalore', 'olympus_rotation', 5, 20, 10),
        ]),
      );
      expect(tie.single.best!.legend, 'Bangalore');
    });
  });

  group('the Legend × Map screen', () {
    final matches = [
      ..._games('Bangalore', 'olympus_rotation', 4, 30, 0),
      ..._games('Axle', 'storm_point_rotation', 5, -10, 10),
    ];

    Future<void> pump(
      WidgetTester tester, {
      String? rankedNow,
      List<RankedMatch>? games,
    }) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            mapRotationProvider.overrideWith(
              (ref) async => rankedNow == null
                  ? throw Exception('offline')
                  : ApiResult(_rotation(rankedNow)),
            ),
          ],
          child: MaterialApp(
            home: RankedLegendMapMatrixScreen(matches: games ?? matches),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('lists each map with your record and best legend', (
      tester,
    ) async {
      await pump(tester, rankedNow: 'Olympus');

      expect(find.text('BEST AND WORST LEGEND PER MAP'), findsOneWidget);
      expect(find.text('Overall: +30.0 RP/game, 4 games'), findsOneWidget);
      expect(
        find.text('Best: Bangalore (+30.0 RP/game, 4 games)'),
        findsOneWidget,
      );
      expect(find.text('Best: Axle (-10.0 RP/game, 5 games)'), findsOneWidget);
    });

    testWidgets(
      'marks the map in the live ranked rotation and lists it first',
      (tester) async {
        await pump(tester, rankedNow: 'Storm Point');

        expect(find.text('PLAYING NOW'), findsOneWidget);
        // The cards, which come after the grid and its column headers.
        final stormTop = tester.getTopLeft(find.text('Storm Point').last).dy;
        final olympusTop = tester.getTopLeft(find.text('Olympus').last).dy;
        expect(stormTop, lessThan(olympusTop));
      },
    );

    testWidgets('without the rotation nothing is marked, and it still works', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('PLAYING NOW'), findsNothing);
      expect(find.text('BEST AND WORST LEGEND PER MAP'), findsOneWidget);
    });

    testWidgets('a legend row shows its icon', (tester) async {
      await pump(tester);

      // One per legend row of the grid: Bangalore and Axle.
      expect(
        find.descendant(
          of: find.byType(Table),
          matching: find.byType(LegendIcon),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('a cell with too few games is faded', (tester) async {
      await pump(
        tester,
        games: [
          ..._games('Bangalore', 'olympus_rotation', 4, 30, 0),
          ..._games('Axle', 'olympus_rotation', 2, 30, 10),
        ],
      );

      double opacityOf(String games) => tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text(games), matching: find.byType(Opacity))
                .first,
          )
          .opacity;
      expect(opacityOf('4'), 1);
      expect(opacityOf('2'), lessThan(1));
    });

    testWidgets('the explanation is behind the info icon, not on the page', (
      tester,
    ) async {
      await pump(tester);
      expect(find.textContaining('A stronger colour'), findsNothing);
      expect(find.textContaining('Tap a cell'), findsNothing);

      await tester.tap(find.byTooltip('How to read this'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('A stronger colour is a bigger gain'),
        findsOne,
      );
      expect(find.textContaining('under 3 games'), findsOneWidget);
      expect(find.text('Tap a cell to see those games.'), findsOneWidget);
    });

    testWidgets('the info sheet scrolls on a small screen', (tester) async {
      await pump(tester);
      tester.view.physicalSize = const Size(360, 420);

      await tester.tap(find.byTooltip('How to read this'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final sheet = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(SingleChildScrollView),
      );
      await tester.drag(sheet, const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('comes first'), findsOneWidget);
    });

    testWidgets('the grid comes first and the best and worst legends below', (
      tester,
    ) async {
      await pump(tester);

      final grid = tester.getTopLeft(find.text('Bangalore').first).dy;
      final section = tester
          .getTopLeft(find.text('BEST AND WORST LEGEND PER MAP'))
          .dy;
      expect(grid, lessThan(section));
    });

    testWidgets('names the worst legend on a map when two have enough games', (
      tester,
    ) async {
      await pump(
        tester,
        games: [
          ..._games('Bangalore', 'olympus_rotation', 4, 30, 0),
          ..._games('Axle', 'olympus_rotation', 5, -10, 10),
        ],
      );

      expect(find.text('Best: Bangalore (+30.0 RP/game, 4 games)'), findsOne);
      expect(find.text('Worst: Axle (-10.0 RP/game, 5 games)'), findsOne);
      expect(find.textContaining('No other legend'), findsNothing);
    });

    testWidgets('with one legend over the line, says so instead', (
      tester,
    ) async {
      await pump(
        tester,
        games: [
          ..._games('Bangalore', 'olympus_rotation', 4, 30, 0),
          ..._games('Axle', 'olympus_rotation', 2, -10, 10),
        ],
      );

      expect(find.textContaining('Worst:'), findsNothing);
      expect(
        find.text('No other legend has 3+ games here yet'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a cell opens that legend\'s games on that map', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('cell|Bangalore|Olympus')));
      await tester.pumpAndSettle();

      expect(find.byType(RankedEntityHistoryScreen), findsOneWidget);
      expect(find.text('Bangalore · Olympus'), findsOneWidget);
      expect(find.text('4 ranked games · +30.0 RP/game'), findsOneWidget);
      // One legend on one map has nothing to group by.
      expect(find.text('Sort:'), findsNothing);
    });

    group('the All row and column, and sorting', () {
      Finder cell(String legend, String map) =>
          find.byKey(ValueKey('cell|$legend|$map'));

      Finder inCell(String legend, String map, String text) =>
          find.descendant(of: cell(legend, map), matching: find.text(text));

      testWidgets('add up each legend, each map and the whole grid', (
        tester,
      ) async {
        await pump(tester);

        // Bangalore: 4 games at +30. Axle: 5 at -10. Together 9 at +7.8.
        expect(inCell('Bangalore', 'All', '4'), findsOneWidget);
        expect(inCell('Bangalore', 'All', '+30.0'), findsOneWidget);
        expect(inCell('Axle', 'All', '-10.0'), findsOneWidget);
        expect(inCell('All', 'Olympus', '4'), findsOneWidget);
        expect(inCell('All', 'Storm Point', '5'), findsOneWidget);
        expect(inCell('All', 'All', '9'), findsOneWidget);
        expect(inCell('All', 'All', '+7.8'), findsOneWidget);
        expect(find.text('All'), findsNWidgets(2)); // the heading and the row
      });

      testWidgets('the All row sits below the legends', (tester) async {
        await pump(tester);

        final bottom = tester.getTopLeft(cell('All', 'Olympus')).dy;
        expect(
          tester.getTopLeft(cell('Bangalore', 'Olympus')).dy,
          lessThan(bottom),
        );
        expect(tester.getTopLeft(cell('Axle', 'Olympus')).dy, lessThan(bottom));
      });

      testWidgets('tapping a legend\'s total opens its games on every map', (
        tester,
      ) async {
        await pump(tester);

        await tester.tap(cell('Bangalore', 'All'));
        await tester.pumpAndSettle();

        expect(find.text('Bangalore · All maps'), findsOneWidget);
        expect(find.text('4 ranked games · +30.0 RP/game'), findsOneWidget);
      });

      testWidgets('tapping a map\'s total opens every legend\'s games there', (
        tester,
      ) async {
        await pump(tester);

        await tester.tap(cell('All', 'Storm Point'));
        await tester.pumpAndSettle();

        expect(find.text('All legends · Storm Point'), findsOneWidget);
        expect(find.text('5 ranked games · -10.0 RP/game'), findsOneWidget);
      });

      testWidgets('tapping the overall total opens every game in the grid', (
        tester,
      ) async {
        await pump(tester);

        await tester.tap(cell('All', 'All'));
        await tester.pumpAndSettle();

        expect(find.text('All legends · All maps'), findsOneWidget);
        expect(find.text('9 ranked games · +7.8 RP/game'), findsOneWidget);
      });

      testWidgets(
        'leave out the column with one map and the row with one legend',
        (tester) async {
          await pump(
            tester,
            games: _games('Bangalore', 'olympus_rotation', 4, 30, 0),
          );

          expect(find.text('All'), findsNothing);
          expect(cell('Bangalore', 'All'), findsNothing);
          expect(cell('All', 'Olympus'), findsNothing);
          // Nothing to put in order either.
          expect(find.text('Most played'), findsNothing);
        },
      );

      // Wraith: 6 games at +5. Bangalore: 4 at +20. Axle: 2 at +50, too few.
      final mixed = [
        ..._games('Wraith', 'olympus_rotation', 6, 5, 0),
        ..._games('Bangalore', 'olympus_rotation', 4, 20, 10),
        ..._games('Axle', 'storm_point_rotation', 2, 50, 20),
      ];

      List<String> rowOrder(WidgetTester tester) {
        final rows = [
          for (final l in ['Wraith', 'Bangalore', 'Axle'])
            (l, tester.getTopLeft(cell(l, 'All')).dy),
        ]..sort((a, b) => a.$2.compareTo(b.$2));
        return [for (final r in rows) r.$1];
      }

      testWidgets('start with the most played legend first', (tester) async {
        await pump(tester, games: mixed);

        expect(find.text('Most played'), findsOneWidget);
        expect(rowOrder(tester), ['Wraith', 'Bangalore', 'Axle']);
      });

      testWidgets('Best RP puts the best average first and few games last', (
        tester,
      ) async {
        await pump(tester, games: mixed);

        await tester.tap(find.text('Best RP'));
        await tester.pump();

        expect(rowOrder(tester), ['Bangalore', 'Wraith', 'Axle']);
      });

      testWidgets('A to Z orders by name', (tester) async {
        await pump(tester, games: mixed);

        await tester.tap(find.text('A–Z'));
        await tester.pump();

        expect(rowOrder(tester), ['Axle', 'Bangalore', 'Wraith']);
      });

      testWidgets('the same choice orders the map columns', (tester) async {
        // Olympus is played more; Storm Point earns more per game.
        await pump(
          tester,
          games: [
            ..._games('Wraith', 'olympus_rotation', 6, 5, 0),
            ..._games('Bangalore', 'storm_point_rotation', 4, 20, 10),
          ],
        );
        double left(String map) => tester.getTopLeft(cell('All', map)).dx;
        expect(left('Olympus'), lessThan(left('Storm Point')));

        await tester.tap(find.text('Best RP'));
        await tester.pump();
        expect(left('Storm Point'), lessThan(left('Olympus')));

        await tester.tap(find.text('A–Z'));
        await tester.pump();
        expect(left('Olympus'), lessThan(left('Storm Point')));
      });

      testWidgets('the info sheet mentions both', (tester) async {
        await pump(tester);

        await tester.tap(find.byTooltip('How to read this'));
        await tester.pumpAndSettle();

        expect(find.textContaining('The All row and column'), findsOneWidget);
        expect(
          find.textContaining('order the legends and maps'),
          findsOneWidget,
        );
      });
    });
  });

  group('matrixCellStrength', () {
    double strength(double avg, int games, {double max = 40}) =>
        matrixCellStrength(avgRp: avg, games: games, maxAbsRp: max);

    test('grows with the size of the gain or loss, either way', () {
      expect(strength(40, 10), greaterThan(strength(20, 10)));
      expect(strength(20, 10), greaterThan(strength(2, 10)));
      expect(strength(-40, 10), strength(40, 10));
    });

    test('is never invisible, and never above the strongest', () {
      expect(strength(0, 10), greaterThan(0));
      expect(strength(400, 10), strength(40, 10));
    });

    test('stays faint for a cell with too few games', () {
      expect(strength(40, 2), lessThanOrEqualTo(0.1));
      expect(strength(40, 2), lessThan(strength(40, 3)));
    });

    test('copes with no swing at all', () {
      expect(strength(0, 10, max: 0), greaterThan(0));
    });
  });
}
