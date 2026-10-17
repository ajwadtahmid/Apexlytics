import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/map_rotation.dart';
import 'package:apexlytics/providers/map_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_legend_map_matrix_screen.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

    Future<void> pump(WidgetTester tester, {String? rankedNow}) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mapRotationProvider.overrideWith(
              (ref) async => rankedNow == null
                  ? throw Exception('offline')
                  : ApiResult(_rotation(rankedNow)),
            ),
          ],
          child: MaterialApp(
            home: RankedLegendMapMatrixScreen(matches: matches),
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

      expect(find.text('BEST LEGEND PER MAP'), findsOneWidget);
      expect(find.text('You: +30.0 RP/game over 4 games'), findsOneWidget);
      expect(
        find.text('Best legend: Bangalore (+30.0 RP/game, 4 games)'),
        findsOneWidget,
      );
      expect(
        find.text('Best legend: Axle (-10.0 RP/game, 5 games)'),
        findsOneWidget,
      );
    });

    testWidgets(
      'marks the map in the live ranked rotation and lists it first',
      (tester) async {
        await pump(tester, rankedNow: 'Storm Point');

        expect(find.text('PLAYING NOW'), findsOneWidget);
        final stormTop = tester.getTopLeft(find.text('Storm Point').first).dy;
        final olympusTop = tester.getTopLeft(find.text('Olympus').first).dy;
        expect(stormTop, lessThan(olympusTop));
      },
    );

    testWidgets('without the rotation nothing is marked, and it still works', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('PLAYING NOW'), findsNothing);
      expect(find.text('BEST LEGEND PER MAP'), findsOneWidget);
    });
  });
}
