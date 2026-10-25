import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/utils/tracking/player_compare.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  CompareLine line(List<CompareLine> lines, String label) =>
      lines.firstWhere((l) => l.label == label);

  LegendTracker t(String name, int value) =>
      buildTracker(key: name.toLowerCase(), displayName: name, value: value);

  LegendStat legend(
    String name, {
    int games = 50,
    int kills = 100,
    int damage = 20000,
    int wins = 5,
    int? revives,
    DateTime? updated,
  }) => LegendStat(
    name: name,
    trackers: [
      t('BR Games Played', games),
      t('BR Kills', kills),
      t('BR Damage', damage),
      t('BR Wins', wins),
      if (revives != null) t('BR Revives', revives),
    ],
    lastUpdated: updated,
  );

  group('rankedCompareLines', () {
    test('counts the rank gap in divisions, not RP', () {
      final lines = rankedCompareLines(
        buildStats(rankScore: 7000), // Gold II
        buildStats(rankScore: 5600), // Gold IV
      );

      expect(line(lines, 'Rank').delta, 2);
      expect(line(lines, 'RP').delta, 1400);
      expect(line(lines, 'RP').valueA, '7,000');
    });

    test('RP needed only says who is closer when both are in one tier', () {
      final same = rankedCompareLines(
        buildStats(rankScore: 5600), // Gold IV
        buildStats(rankScore: 5800), // Gold IV
      );
      final different = rankedCompareLines(
        buildStats(rankScore: 5600), // Gold
        buildStats(rankScore: 4500), // Silver
      );

      // 650 left against 450 left: you need 200 more, and fewer is better.
      expect(line(same, 'RP needed').delta, 200);
      expect(line(same, 'RP needed').invert, isTrue);
      // The divisions of two tiers are different widths, so no verdict.
      expect(line(different, 'RP needed').delta, isNull);
    });

    test('Apex Predator is a step above Master, and has no next rank', () {
      final lines = rankedCompareLines(
        buildStats(rankScore: 21000, rank: 'Apex Predator'),
        buildStats(rankScore: 16500, rank: 'Master'),
      );

      expect(line(lines, 'Rank').delta, 1);
      expect(lines.map((l) => l.label), isNot(contains('Next rank')));
    });
  });

  group('comparableLegends', () {
    test('lists shared legends first, the thinner side deciding the order', () {
      final me = buildStats(
        legendStats: [
          legend('Wraith', games: 100),
          legend('Octane', games: 5),
          legend('Bangalore', games: 50),
        ],
      );
      final them = buildStats(
        legendStats: [
          legend('Wraith', games: 30),
          legend('Octane', games: 200),
          legend('Pathfinder', games: 10),
        ],
      );

      // Wraith: 30 on the thinner side, Octane: 5. Then those only one has.
      expect(comparableLegends(me, them), [
        'Wraith',
        'Octane',
        'Bangalore',
        'Pathfinder',
      ]);
    });

    test('leaves out a legend with no trackers, and is empty with none', () {
      expect(
        comparableLegends(
          buildStats(
            legendStats: [const LegendStat(name: 'Wraith', trackers: [])],
          ),
          buildStats(),
        ),
        isEmpty,
      );
    });
  });

  group('legendOptions', () {
    test('carries each legend\'s games, and whether you both have it', () {
      final options = legendOptions(
        buildStats(
          legendStats: [
            legend('Wraith', games: 100),
            legend('Bangalore', games: 9),
          ],
        ),
        buildStats(legendStats: [legend('Wraith', games: 30)]),
      );

      expect(options.map((o) => o.name), ['Wraith', 'Bangalore']);
      expect(options.first.gamesA, 100);
      expect(options.first.gamesB, 30);
      expect(options.first.shared, isTrue);
      expect(options.last.gamesB, isNull);
      expect(options.last.shared, isFalse);
    });
  });

  group('legendCompare', () {
    final me = buildStats(
      legendStats: [legend('Wraith', games: 50, kills: 100, damage: 20000)],
    );
    final them = buildStats(
      legendStats: [legend('Wraith', games: 20, kills: 60, damage: 9000)],
    );

    test('compares per-game rates, not totals', () {
      final data = legendCompare(me, them, 'Wraith');

      expect(line(data.calculated, 'Damage per Kill').delta, 50); // 200 vs 150
      expect(line(data.calculated, 'Damage per Kill').integerDelta, isTrue);
      expect(line(data.calculated, 'Avg Kills per Game').valueA, '2.0');
      expect(line(data.calculated, 'Avg Kills per Game').valueB, '3.0');
      expect(
        line(data.calculated, 'Avg Kills per Game').delta,
        closeTo(-1, 1e-9),
      );
    });

    test('shows a revive rate gap in hundredths, so it is not lost', () {
      final data = legendCompare(
        buildStats(legendStats: [legend('Wraith', games: 50, revives: 10)]),
        buildStats(legendStats: [legend('Wraith', games: 20, revives: 2)]),
        'Wraith',
      );

      final row = line(data.calculated, 'Revive Rate');
      expect(row.decimals, 2);
      expect(row.delta, closeTo(0.10, 1e-9)); // 0.20 against 0.10
    });

    test('lists the trackers under their own names, with a gap where both '
        'have one', () {
      final data = legendCompare(me, them, 'Wraith');

      expect(line(data.trackers, 'BR Kills').delta, 40);
      expect(line(data.trackers, 'BR Kills').valueA, '100');
    });

    test('puts the main trackers first, games played with no verdict', () {
      final data = legendCompare(
        buildStats(
          legendStats: [
            LegendStat(
              name: 'Ash',
              trackers: [
                t('Arc Snare: Enemies Tethered', 926),
                t('BR Wins', 3),
                t('BR Damage', 500),
                t('BR Kills', 9),
                t('BR Games Played', 7),
              ],
            ),
          ],
        ),
        buildStats(),
        'Ash',
      );

      expect(data.trackers.map((l) => l.label), [
        'BR Games Played',
        'BR Kills',
        'BR Damage',
        'BR Wins',
        'Arc Snare: Enemies Tethered',
      ]);
      // Played more is not better, and one side has nothing to compare anyway.
      expect(data.trackers.first.delta, isNull);
    });

    test('games played has no verdict even when both have it', () {
      final data = legendCompare(me, them, 'Wraith');

      expect(line(data.trackers, 'BR Games Played').delta, isNull);
    });

    test('a side with no figure shows a dash and no verdict', () {
      final data = legendCompare(
        buildStats(),
        buildStats(legendStats: [legend('Wraith')]),
        'Wraith',
      );

      final row = line(data.calculated, 'Win Rate');
      expect(row.valueA, '—');
      expect(row.delta, isNull);
    });

    test('never divides by zero when a legend has no games or kills', () {
      final data = legendCompare(
        buildStats(
          legendStats: [legend('Wraith', games: 0, kills: 0, damage: 0)],
        ),
        them,
        'Wraith',
      );

      // Nothing can be worked out for the side with no games.
      expect(data.calculated.every((r) => r.valueA == '—'), isTrue);
    });

    test('flags a small sample on either side, but not an unknown one', () {
      final few = buildStats(legendStats: [legend('Wraith', games: 2)]);

      expect(legendCompare(few, them, 'Wraith').lowSample, isTrue);
      expect(legendCompare(me, them, 'Wraith').lowSample, isFalse);
      expect(
        legendCompare(
          buildStats(
            legendStats: [
              LegendStat(name: 'Wraith', trackers: [t('BR Kills', 9)]),
            ],
          ),
          me,
          'Wraith',
        ).lowSample,
        isFalse,
      );
    });

    test('is empty when neither player has the legend', () {
      expect(legendCompare(me, them, 'Octane').isEmpty, isTrue);
    });
  });
}
