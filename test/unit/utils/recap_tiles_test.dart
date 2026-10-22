import 'package:apexlytics/utils/ranked/best_metric.dart';
import 'package:apexlytics/utils/ranked/recap_tiles.dart';
import 'package:apexlytics/utils/ranked/split_recap.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  final t0 = 1782090000;

  // Four wins on one legend and map: a best legend, map and session.
  final enough = splitRecap([
    for (var i = 0; i < 4; i++)
      buildMatch(start: t0 + i * 1500, rp: 20, cumulativeRp: 1020 + i * 20),
  ], metric: BestMetric.totalRp);
  // Three losses, each on another legend and map: no best of either.
  final scattered = splitRecap([
    buildMatch(start: t0, rp: -20, legend: 'Axle', map: 'olympus_rotation'),
    buildMatch(
      start: t0 + 1500,
      rp: -20,
      legend: 'Wraith',
      map: 'worlds_edge_rotation',
    ),
    buildMatch(
      start: t0 + 3000,
      rp: -20,
      legend: 'Octane',
      map: 'kings_canyon_rotation',
    ),
  ], metric: BestMetric.totalRp);

  test('the tiles are in the card\'s order, two to a row', () {
    expect(RecapTile.values, [
      RecapTile.games,
      RecapTile.peakRp,
      RecapTile.kills,
      RecapTile.damage,
      RecapTile.bestSession,
      RecapTile.timePlayed,
      RecapTile.bestLegend,
      RecapTile.bestMap,
      RecapTile.winRate,
      RecapTile.rpPerGame,
    ]);
  });

  test('every tile is on by default except the win rate and RP per game', () {
    expect(
      defaultRecapTiles,
      RecapTile.values
          .where((t) => t != RecapTile.winRate && t != RecapTile.rpPerGame)
          .toSet(),
    );
    expect(defaultRecapTiles.length, 8);
  });

  test('the default tiles fill whole rows', () {
    expect(defaultRecapTiles.length.isEven, isTrue);
  });

  group('availableRecapTiles', () {
    test('has all ten when there is something behind each', () {
      expect(availableRecapTiles(enough), RecapTile.values.toSet());
    });

    test('leaves out the best legend and map when none played enough', () {
      final tiles = availableRecapTiles(scattered);

      expect(tiles, isNot(contains(RecapTile.bestLegend)));
      expect(tiles, isNot(contains(RecapTile.bestMap)));
      expect(tiles, contains(RecapTile.games));
    });

    test('keeps the win rate and RP per game whatever happened', () {
      final tiles = availableRecapTiles(scattered);

      expect(tiles, contains(RecapTile.winRate));
      expect(tiles, contains(RecapTile.rpPerGame));
      expect(tiles, contains(RecapTile.bestSession));
    });
  });

  group('shownRecapTiles', () {
    test('is what was chosen, in the card\'s order', () {
      final shown = shownRecapTiles({
        RecapTile.timePlayed,
        RecapTile.games,
        RecapTile.damage,
      }, RecapTile.values.toSet());

      expect(shown, [RecapTile.games, RecapTile.damage, RecapTile.timePlayed]);
    });

    test('drops a chosen tile that has nothing to show', () {
      final shown = shownRecapTiles({
        RecapTile.games,
        RecapTile.winRate,
        RecapTile.rpPerGame,
        RecapTile.bestLegend,
      }, availableRecapTiles(scattered));

      // The best legend has nothing behind it here.
      expect(shown, [RecapTile.games, RecapTile.winRate, RecapTile.rpPerGame]);
    });

    test('can turn on the win rate and RP per game when asked', () {
      final shown = shownRecapTiles({
        ...defaultRecapTiles,
        RecapTile.winRate,
        RecapTile.rpPerGame,
      }, availableRecapTiles(enough));

      expect(shown, RecapTile.values);
    });

    test('does not show them unless asked', () {
      final shown = shownRecapTiles(
        defaultRecapTiles,
        availableRecapTiles(enough),
      );

      expect(shown, isNot(contains(RecapTile.winRate)));
      expect(shown, isNot(contains(RecapTile.rpPerGame)));
    });

    test('falls back to the defaults when too few of the choice remain', () {
      final available = availableRecapTiles(scattered);

      // A choice of two tiles that this period can't show.
      final shown = shownRecapTiles({
        RecapTile.bestLegend,
        RecapTile.rpPerGame,
      }, available);

      expect(shown, [
        for (final t in RecapTile.values)
          if (defaultRecapTiles.contains(t) && available.contains(t)) t,
      ]);
      expect(shown.length, greaterThanOrEqualTo(kMinRecapTiles));
    });
  });
}
