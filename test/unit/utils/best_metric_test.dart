import 'package:apexlytics/utils/ranked/best_metric.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LegendBreakdown legend(
    String name, {
    required int games,
    int rp = 0,
    int wins = 0,
    int losses = 0,
    int kills = 0,
    int? killsGames,
    int damage = 0,
    int? damageGames,
  }) => LegendBreakdown(
    legend: name,
    games: games,
    totalRp: rp,
    totalKills: kills,
    totalDamage: damage,
    killsGames: killsGames ?? games,
    damageGames: damageGames ?? games,
    totalLengthSecs: 0,
    wins: wins,
    losses: losses,
  );

  List<String> order(
    Iterable<LegendBreakdown> items,
    BestMetric metric, {
    bool softGate = false,
  }) => [
    for (final l in rankByMetric(
      items,
      metric,
      nameOf: (l) => l.legend,
      softGate: softGate,
    ))
      l.legend,
  ];

  group('BestMetric.valueOf', () {
    final tally = legend(
      'A',
      games: 10,
      rp: 100,
      wins: 6,
      losses: 3,
      kills: 25,
      damage: 5000,
    );

    test('reads each measure', () {
      expect(BestMetric.rpPerGame.valueOf(tally), 10);
      expect(BestMetric.totalRp.valueOf(tally), 100);
      expect(BestMetric.avgKills.valueOf(tally), 2.5);
      expect(BestMetric.totalKills.valueOf(tally), 25);
      expect(BestMetric.avgDamage.valueOf(tally), 500);
      expect(BestMetric.totalDamage.valueOf(tally), 5000);
      // One of the ten games moved no RP, so it is not decided.
      expect(BestMetric.winRate.valueOf(tally), closeTo(6 / 9, 1e-9));
    });

    test('kills and damage divide by the games that reported them', () {
      final partial = legend(
        'A',
        games: 10,
        kills: 12,
        killsGames: 4,
        damage: 3000,
        damageGames: 6,
      );

      expect(BestMetric.avgKills.valueOf(partial), 3);
      expect(BestMetric.avgDamage.valueOf(partial), 500);
    });

    test(
      'has no figure where nothing was reported, but a reported 0 is one',
      () {
        final unreported = legend('A', games: 5, killsGames: 0, damageGames: 0);
        for (final m in [
          BestMetric.avgKills,
          BestMetric.totalKills,
          BestMetric.avgDamage,
          BestMetric.totalDamage,
        ]) {
          expect(m.valueOf(unreported), isNull, reason: '$m');
        }

        final scoreless = legend('A', games: 5, kills: 0, damage: 0);
        expect(BestMetric.avgKills.valueOf(scoreless), 0);
        expect(BestMetric.totalDamage.valueOf(scoreless), 0);
      },
    );

    test('has no win rate without a game that moved RP', () {
      expect(BestMetric.winRate.valueOf(legend('A', games: 4)), isNull);
    });

    test('has no figure at all without games', () {
      for (final m in BestMetric.values) {
        expect(m.valueOf(legend('A', games: 0)), isNull, reason: '$m');
      }
    });
  });

  group('the measures', () {
    test(
      'are listed in the picker\'s order, Total RP first and the default',
      () {
        expect(BestMetric.values, [
          BestMetric.totalRp,
          BestMetric.rpPerGame,
          BestMetric.winRate,
          BestMetric.avgKills,
          BestMetric.totalKills,
          BestMetric.avgDamage,
          BestMetric.totalDamage,
        ]);
        expect(kDefaultBestMetric, BestMetric.totalRp);
      },
    );

    test('the one per game is called Avg RP, as it is on the stat row', () {
      expect(BestMetric.rpPerGame.label, 'Avg RP');
      expect(BestMetric.rpPerGame.phrase, 'avg RP');
    });
  });

  group('how a measure is shown', () {
    test('a pill and a line of text write each figure with its unit', () {
      final shown = {
        BestMetric.rpPerGame: ('+80.1 /game', '+80.1 RP/game'),
        BestMetric.totalRp: ('+1,084 RP', '+1,084 RP'),
        BestMetric.avgKills: ('2.8 kills/game', '2.8 kills/game'),
        BestMetric.totalKills: ('1,204 kills', '1,204 kills'),
        BestMetric.avgDamage: ('521 dmg/game', '521 dmg/game'),
        BestMetric.totalDamage: ('23,760 dmg', '23,760 dmg'),
        BestMetric.winRate: ('62% win rate', '62% win rate'),
      };
      final values = {
        BestMetric.rpPerGame: 80.1,
        BestMetric.totalRp: 1084.0,
        BestMetric.avgKills: 2.8,
        BestMetric.totalKills: 1204.0,
        BestMetric.avgDamage: 520.6,
        BestMetric.totalDamage: 23760.0,
        BestMetric.winRate: 0.62,
      };
      for (final m in BestMetric.values) {
        expect(m.formatValue(values[m]!), shown[m]!.$1, reason: '$m');
        expect(m.formatInline(values[m]!), shown[m]!.$2, reason: '$m');
      }
    });

    test('a loss is written with its sign', () {
      expect(BestMetric.rpPerGame.formatValue(-39.6), '-39.6 /game');
      expect(BestMetric.totalRp.formatValue(-198), '-198 RP');
    });

    test('only the RP measures can be a loss', () {
      expect(
        {
          for (final m in BestMetric.values)
            if (m.isRp) m,
        },
        {BestMetric.rpPerGame, BestMetric.totalRp},
      );
    });

    test('each has a label and a phrase of its own', () {
      for (final field in [
        (BestMetric m) => m.label,
        (BestMetric m) => m.phrase,
      ]) {
        final all = [for (final m in BestMetric.values) field(m)];
        expect(all.every((t) => t.isNotEmpty), isTrue);
        expect(all.toSet().length, all.length, reason: '$all');
      }
    });
  });

  group('rankByMetric', () {
    // Each of the three leads under a different measure.
    final a = legend(
      'A',
      games: 10,
      rp: 100,
      wins: 6,
      losses: 4,
      kills: 20,
      damage: 5000,
    );
    final b = legend(
      'B',
      games: 4,
      rp: 60,
      wins: 4,
      losses: 0,
      kills: 12,
      damage: 3200,
    );
    final c = legend(
      'C',
      games: 20,
      rp: 80,
      wins: 9,
      losses: 11,
      kills: 80,
      damage: 6000,
    );

    test('orders by the chosen measure, best first', () {
      final expected = {
        BestMetric.rpPerGame: ['B', 'A', 'C'],
        BestMetric.totalRp: ['A', 'C', 'B'],
        BestMetric.avgKills: ['C', 'B', 'A'],
        BestMetric.totalKills: ['C', 'A', 'B'],
        BestMetric.avgDamage: ['B', 'A', 'C'],
        BestMetric.totalDamage: ['C', 'A', 'B'],
        BestMetric.winRate: ['B', 'A', 'C'],
      };
      for (final entry in expected.entries) {
        expect(
          order([a, b, c], entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('does not depend on the order the items arrive in', () {
      for (final m in BestMetric.values) {
        expect(order([c, a, b], m), order([b, c, a], m), reason: '$m');
      }
    });

    test('a tie goes to the legend with more games, then to the name', () {
      final x = legend('X', games: 5, rp: 50);
      final y = legend('Y', games: 8, rp: 80);
      final w = legend('W', games: 8, rp: 80);

      // All 10 RP a game: the 8-game ones first, W before Y, then X.
      expect(order([x, y, w], BestMetric.rpPerGame), ['W', 'Y', 'X']);
    });

    group('with fewer than the minimum games', () {
      final thin = legend('Thin', games: kMinGamesForInsight - 1, rp: 500);
      final solid = legend('Solid', games: kMinGamesForInsight, rp: 30);

      test('they are left out', () {
        expect(order([thin, solid], BestMetric.rpPerGame), ['Solid']);
        expect(order([thin], BestMetric.rpPerGame), isEmpty);
      });

      test('a soft gate ranks them only when nothing else qualifies', () {
        expect(order([thin, solid], BestMetric.rpPerGame, softGate: true), [
          'Solid',
        ]);
        expect(
          order(
            [thin, legend('Thinner', games: 1, rp: 90)],
            BestMetric.rpPerGame,
            softGate: true,
          ),
          ['Thin', 'Thinner'], // 250 a game against 90
        );
      });
    });

    test('an item with no figure is left out, even under a soft gate', () {
      final unreported = legend(
        'Quiet',
        games: 6,
        rp: 90,
        killsGames: 0,
        damageGames: 0,
      );
      final reported = legend('Loud', games: 6, kills: 6, rp: 10);

      expect(order([unreported, reported], BestMetric.avgKills), ['Loud']);
      expect(
        order([unreported, reported], BestMetric.avgKills, softGate: true),
        ['Loud'],
      );
      // Every other measure still has a figure for it.
      expect(order([unreported, reported], BestMetric.rpPerGame), [
        'Quiet',
        'Loud',
      ]);
    });

    test('a legend that scored nothing ranks, last, rather than vanishing', () {
      final scoreless = legend('Zero', games: 4, kills: 0);
      final scorer = legend('Scorer', games: 4, kills: 8);

      expect(order([scoreless, scorer], BestMetric.avgKills), [
        'Scorer',
        'Zero',
      ]);
    });
  });

  group('sortByMetric', () {
    final a = legend('A', games: 10, rp: 100, kills: 20, damage: 5000);
    final b = legend('B', games: 2, rp: 60, kills: 12, damage: 3200);
    final c = legend('C', games: 20, rp: 80, kills: 80, damage: 6000);

    List<String> sorted(Iterable<LegendBreakdown> items, BestMetric m) => [
      for (final l in sortByMetric(items, m, nameOf: (l) => l.legend)) l.legend,
    ];

    test('puts the biggest first, whatever the games, nothing left out', () {
      // B has too few games to be ranked, but a list being sorted keeps it.
      expect(sorted([a, b, c], BestMetric.totalRp), ['A', 'C', 'B']);
      expect(sorted([a, b, c], BestMetric.rpPerGame), ['B', 'A', 'C']);
      expect(sorted([a, b, c], BestMetric.totalKills), ['C', 'A', 'B']);
    });

    test('an item with no figure goes last, either way round the others', () {
      final quiet = legend('Quiet', games: 9, killsGames: 0, damageGames: 0);

      expect(sorted([quiet, a, c], BestMetric.avgKills), ['C', 'A', 'Quiet']);
      expect(sorted([a, quiet, c], BestMetric.avgDamage), ['A', 'C', 'Quiet']);
    });

    test(
      'a tie goes to more games, then the name, whatever the input order',
      () {
        final x = legend('X', games: 5, rp: 50);
        final y = legend('Y', games: 8, rp: 80);
        final w = legend('W', games: 8, rp: 80);

        expect(sorted([x, y, w], BestMetric.rpPerGame), ['W', 'Y', 'X']);
        expect(sorted([w, x, y], BestMetric.rpPerGame), ['W', 'Y', 'X']);
      },
    );
  });

  group('bestAndWorst', () {
    final high = legend('High', games: 5, rp: 100);
    final mid = legend('Mid', games: 5, rp: 50);
    final low = legend('Low', games: 5, rp: 10);

    ({String? best, String? worst}) names(List<LegendBreakdown> ranked) {
      final r = bestAndWorst(ranked, BestMetric.rpPerGame);
      return (best: r.best?.legend, worst: r.worst?.legend);
    }

    test('names the top and the bottom', () {
      expect(names([high, mid, low]), (best: 'High', worst: 'Low'));
    });

    test('has neither with nothing, and no worst with one', () {
      expect(names([]), (best: null, worst: null));
      expect(names([high]), (best: 'High', worst: null));
    });

    test('has no worst when the bottom is no lower than the top', () {
      final same = legend('Same', games: 5, rp: 100);
      expect(names([high, same]), (best: 'High', worst: null));
    });

    test('of several equally weak, takes the one with the most games', () {
      final weakFew = legend('WeakFew', games: 3, rp: 3);
      final weakMany = legend('WeakMany', games: 6, rp: 6);

      final ranked = rankByMetric(
        [high, weakFew, weakMany],
        BestMetric.rpPerGame,
        nameOf: (l) => l.legend,
      );

      expect(names(ranked), (best: 'High', worst: 'WeakMany'));
    });
  });
}
