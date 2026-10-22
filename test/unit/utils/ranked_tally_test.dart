import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Three games on one legend and map: +30 RP in all, two games up and one
  // down, with kills and damage reported for two of them.
  const legend = LegendBreakdown(
    legend: 'Axle',
    games: 3,
    totalRp: 30,
    totalKills: 6,
    totalDamage: 1200,
    killsGames: 2,
    damageGames: 2,
    totalLengthSecs: 900,
    wins: 2,
    losses: 1,
  );
  const map = MapBreakdown(
    mapKey: 'olympus_rotation',
    displayName: 'Olympus',
    games: 3,
    totalRp: 30,
    totalKills: 6,
    totalDamage: 1200,
    killsGames: 2,
    damageGames: 2,
    totalLengthSecs: 900,
    wins: 2,
    losses: 1,
  );
  const cell = LegendMapCell(
    legend: 'Axle',
    mapName: 'Olympus',
    games: 3,
    totalRp: 30,
    wins: 2,
    losses: 1,
    totalKills: 6,
    killsGames: 2,
    totalDamage: 1200,
    damageGames: 2,
  );

  for (final (name, tally) in <(String, RankedTally)>[
    ('a legend', legend),
    ('a map', map),
    ('a legend on a map', cell),
  ]) {
    test('$name gives the same averages', () {
      expect(tally.avgRpPerGame, 10);
      expect(tally.avgKills, 3);
      expect(tally.avgDamage, 600);
      expect(tally.decidedGames, 3);
      expect(tally.winRate, closeTo(2 / 3, 1e-9));
    });
  }

  test('a group with nothing reported has no kill or damage average', () {
    const bare = LegendMapCell(
      legend: 'Axle',
      mapName: 'Olympus',
      games: 4,
      totalRp: 8,
    );

    expect(bare.avgRpPerGame, 2);
    expect(bare.avgKills, isNull);
    expect(bare.avgDamage, isNull);
    expect(bare.winRate, 0);
  });

  test('an empty group averages to nothing', () {
    const empty = LegendMapCell(
      legend: 'Axle',
      mapName: 'Olympus',
      games: 0,
      totalRp: 0,
    );

    expect(empty.avgRpPerGame, 0);
    expect(empty.winRate, 0);
  });

  test('the games needed for an insight come with the aggregates', () {
    expect(kMinGamesForInsight, 3);
  });
}
