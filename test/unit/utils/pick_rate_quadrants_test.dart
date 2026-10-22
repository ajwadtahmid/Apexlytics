import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/ranked/best_metric.dart';
import 'package:apexlytics/utils/ranked/pick_rate_quadrants.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

List<RankedMatch> _games(String legend, int n, int rp) => [
  for (var i = 0; i < n; i++)
    buildMatch(
      legend: legend,
      rp: rp,
      start: 1782090000 + legend.hashCode % 1000 + i * 5000,
    ),
];

void main() {
  group('quadrantOf', () {
    test('crosses pick rate with RP against the two lines', () {
      expect(quadrantOf(0.4, 5, 0.3, 0), PickRateQuadrant.core);
      expect(quadrantOf(0.4, -5, 0.3, 0), PickRateQuadrant.trap);
      expect(quadrantOf(0.1, 5, 0.3, 0), PickRateQuadrant.hiddenGem);
      expect(quadrantOf(0.1, -5, 0.3, 0), PickRateQuadrant.bench);
    });

    test('a legend exactly on a line counts as high and as good', () {
      expect(quadrantOf(0.3, 0, 0.3, 0), PickRateQuadrant.core);
    });

    test('the RP line can be the player\'s own average', () {
      expect(quadrantOf(0.4, 5, 0.3, 12), PickRateQuadrant.trap);
    });
  });

  group('pickRateTakeaways', () {
    List<PickRateTakeaway> takeaways(
      List<RankedMatch> matches, {
      double baseline = 0,
    }) {
      final pool = legendBreakdowns(matches);
      final total = pool.fold(0, (n, l) => n + l.games);
      return pickRateTakeaways(
        pool: pool,
        totalGames: total,
        equalShareRate: 1 / pool.length,
        rpBaseline: baseline,
      );
    }

    test('names the comfort trap and the hidden gem', () {
      final found = takeaways([
        ..._games('Alter', 8, -5), // half the games, losing RP
        ..._games('Bangalore', 4, 20), // played less, winning
        ..._games('Wraith', 4, -3),
      ]);

      expect(found.map((t) => t.quadrant), [
        PickRateQuadrant.trap,
        PickRateQuadrant.hiddenGem,
      ]);
      expect(found[0].legend.legend, 'Alter');
      expect(found[0].pickRate, 0.5);
      expect(found[1].legend.legend, 'Bangalore');
    });

    test('picks the most played trap and the best gem', () {
      final found = takeaways([
        ..._games('Alter', 10, -2),
        ..._games('Loba', 7, -9), // also losing, but played less than Alter
        ..._games('Wraith', 3, 10),
        ..._games('Seer', 3, 25), // the better gem
      ]);

      expect(found.map((t) => t.legend.legend), ['Alter', 'Seer']);
    });

    test('never names a legend with too few games', () {
      final found = takeaways([
        ..._games('Alter', 10, 5),
        ..._games('Wraith', 2, 40), // a great run over two games
      ]);

      expect(found, isEmpty);
    });

    test('has nothing to say when no legend is a trap or a gem', () {
      expect(takeaways([..._games('Alter', 8, 5)]), isEmpty);
      expect(
        takeaways([..._games('Alter', 6, 5), ..._games('Wraith', 6, 5)]),
        isEmpty,
      );
    });

    test('follows the baseline it is given', () {
      final matches = [..._games('Alter', 8, 4), ..._games('Wraith', 4, 9)];
      // Against 0 RP, Alter is a main and only Wraith stands out.
      expect(takeaways(matches).map((t) => t.quadrant), [
        PickRateQuadrant.hiddenGem,
      ]);
      // Against an average of +6, Alter is a trap as well.
      expect(takeaways(matches, baseline: 6).map((t) => t.quadrant), [
        PickRateQuadrant.trap,
        PickRateQuadrant.hiddenGem,
      ]);
    });

    test('is empty with no games', () {
      expect(
        pickRateTakeaways(
          pool: const [],
          totalGames: 0,
          equalShareRate: 0,
          rpBaseline: 0,
        ),
        isEmpty,
      );
    });
  });

  group('legendBestWorstMap', () {
    // These are about RP per game, whatever measure is the default.
    ({LegendMapCell? best, LegendMapCell? worst}) perGame(
      List<LegendMapCell> cells,
    ) => legendBestWorstMap(cells, metric: BestMetric.avgRp);

    LegendMapCell cell(String map, int games, int totalRp) => LegendMapCell(
      legend: 'Alter',
      mapName: map,
      games: games,
      totalRp: totalRp,
    );

    test('names the best and the worst of the maps with enough games', () {
      final r = perGame([
        cell('Olympus', 4, 40),
        cell('Kings Canyon', 5, -25),
        cell('Storm Point', 3, 3),
      ]);

      expect(r.best?.mapName, 'Olympus');
      expect(r.worst?.mapName, 'Kings Canyon');
    });

    test('leaves out a map with fewer than the minimum games', () {
      final r = perGame([
        cell('Olympus', 4, 40),
        cell('Kings Canyon', 2, -100),
        cell('Storm Point', 3, -3),
      ]);

      expect(r.worst?.mapName, 'Storm Point');
    });

    test('has no worst when one map qualifies', () {
      final r = perGame([
        cell('Olympus', 4, 40),
        cell('Kings Canyon', 1, -20),
      ]);

      expect(r.best?.mapName, 'Olympus');
      expect(r.worst, isNull);
    });

    test('has no worst when the maps do equally well', () {
      final r = perGame([
        cell('Olympus', 4, 20),
        cell('Kings Canyon', 6, 30),
      ]);

      expect(r.best, isNotNull);
      expect(r.worst, isNull);
    });

    test('a tie for worst goes to the map with more games', () {
      final r = perGame([
        cell('Olympus', 3, 30),
        cell('Kings Canyon', 3, -15),
        cell('Storm Point', 6, -30),
      ]);

      expect(r.worst?.mapName, 'Storm Point');
    });

    test('follows the chosen measure', () {
      // Olympus pays more a game; Storm Point is where the kills come.
      LegendMapCell on(String map, int rp, int kills) => LegendMapCell(
        legend: 'Alter',
        mapName: map,
        games: 4,
        totalRp: rp,
        totalKills: kills,
        killsGames: 4,
      );
      final cells = [on('Olympus', 80, 4), on('Storm Point', 20, 16)];

      final byRp = perGame(cells);
      expect(byRp.best?.mapName, 'Olympus');
      expect(byRp.worst?.mapName, 'Storm Point');

      final byKills = legendBestWorstMap(cells, metric: BestMetric.avgKills);
      expect(byKills.best?.mapName, 'Storm Point');
      expect(byKills.worst?.mapName, 'Olympus');
    });

    test('has neither when no map has enough games', () {
      final r = perGame([cell('Olympus', 2, 40)]);

      expect(r.best, isNull);
      expect(r.worst, isNull);
    });
  });

  group('pickRatePool', () {
    final legends = legendBreakdowns([
      ..._games('Alter', 5, 10),
      ..._games('Bangalore', 2, 10),
      ..._games('Wraith', 3, 10),
    ]);

    test('keeps only legends with enough games by default', () {
      final pool = pickRatePool(legends, showAll: false);

      expect({for (final l in pool) l.legend}, {'Alter', 'Wraith'});
    });

    test('keeps every legend when asked', () {
      expect(pickRatePool(legends, showAll: true), legends);
    });
  });

  group('legendsMovedByBaseline', () {
    // Alter: 8 games at +10. Bangalore: 4 at +2. Wraith: 4 at -6.
    final pool = legendBreakdowns([
      ..._games('Alter', 8, 10),
      ..._games('Bangalore', 4, 2),
      ..._games('Wraith', 4, -6),
    ]);

    int moved(double average) => legendsMovedByBaseline(
      pool,
      totalGames: 16,
      equalShareRate: 1 / 3,
      ownAverage: average,
    );

    test('counts legends that cross the new line', () {
      // Bangalore (+2) falls below an average of +5; so does Wraith, but it
      // was already below 0 and is still below it.
      expect(moved(5), 1);
    });

    test('is zero when the average is 0', () {
      expect(moved(0), 0);
    });

    test('is zero when no legend sits between 0 and the average', () {
      expect(moved(1), 0);
    });

    test('counts a legend that rises above a negative average', () {
      // Wraith (-6) is below 0 but above an average of -8.
      expect(moved(-8), 1);
    });
  });
}
