import 'package:apexlytics/utils/ranked/best_metric.dart';
import 'package:apexlytics/utils/ranked/split_recap.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  // Two sessions a day apart: Axle wins on Olympus, then Wraith loses.
  final t0 = 1782090000;
  final games = [
    buildMatch(start: t0, rp: 20, cumulativeRp: 1020, kills: 3, damage: 500),
    buildMatch(
      start: t0 + 1500,
      rp: 30,
      cumulativeRp: 1050,
      kills: 5,
      damage: 900,
    ),
    buildMatch(
      start: t0 + 3000,
      rp: -10,
      cumulativeRp: 1040,
      kills: 1,
      damage: 200,
    ),
    buildMatch(
      start: t0 + 86400,
      legend: 'Wraith',
      map: 'storm_point_rotation',
      rp: -20,
      cumulativeRp: 1020,
      kills: 0,
      damage: 100,
    ),
    buildMatch(
      start: t0 + 86400 + 1500,
      legend: 'Wraith',
      map: 'storm_point_rotation',
      rp: -20,
      cumulativeRp: 1000,
      kills: 1,
      damage: 150,
    ),
    buildMatch(
      start: t0 + 86400 + 3000,
      legend: 'Wraith',
      map: 'storm_point_rotation',
      rp: -10,
      cumulativeRp: 990,
      kills: 0,
      damage: 50,
    ),
  ];

  test('totals, peak and where the player finished', () {
    final r = splitRecap(games, metric: BestMetric.totalRp);

    expect(r.games, 6);
    expect(r.wins, 2);
    expect(r.losses, 4);
    expect(r.netRp, 20 + 30 - 10 - 20 - 20 - 10);
    expect(r.peakRp, 1050);
    expect(r.finalRp, 990);
    expect(r.totalKills, 10);
    expect(r.playSecs, 6 * 600);
  });

  test('best legend and map are by RP per game, with enough games', () {
    final r = splitRecap(games, metric: BestMetric.totalRp);

    expect(r.bestLegend!.legend, 'Axle');
    expect(r.bestMap!.displayName, 'Olympus');
  });

  test('best legend and map follow the chosen measure', () {
    // Axle earns more a game; Octane earns more in all, and scores more.
    final r = [
      for (var i = 0; i < 3; i++)
        buildMatch(start: t0 + i * 1000, rp: 10, kills: 1, damage: 100),
      for (var i = 0; i < 10; i++)
        buildMatch(
          start: t0 + 86400 + i * 1000,
          legend: 'Octane',
          map: 'storm_point_rotation',
          rp: 4,
          kills: 3,
          damage: 400,
        ),
    ];

    for (final (metric, legend, map) in [
      (BestMetric.avgRp, 'Axle', 'Olympus'),
      (BestMetric.totalRp, 'Octane', 'Storm Point'),
      (BestMetric.avgKills, 'Octane', 'Storm Point'),
      (BestMetric.totalDamage, 'Octane', 'Storm Point'),
    ]) {
      final recap = splitRecap(r, metric: metric);
      expect(recap.bestLegend!.legend, legend, reason: '$metric');
      expect(recap.bestMap!.displayName, map, reason: '$metric');
    }
  });

  test('no legend reported kills: there is no best by kills', () {
    final r = splitRecap([
      for (var i = 0; i < 4; i++) buildMatch(start: t0 + i * 1000, rp: 10),
    ], metric: BestMetric.avgKills);

    expect(r.bestLegend, isNull);
    expect(r.bestMap, isNull);
  });

  test('a legend with too few games is not the best', () {
    final r = splitRecap([
      ...games,
      buildMatch(
        start: t0 + 9 * 86400,
        legend: 'Octane',
        rp: 90,
        cumulativeRp: 1080,
      ),
    ], metric: BestMetric.totalRp);

    expect(r.bestLegend!.legend, 'Axle');
  });

  test(
    'best session gained the most RP, and the streak counts wins in a row',
    () {
      final r = splitRecap(games, metric: BestMetric.totalRp);

      expect(r.bestSession!.netRp, 40);
      expect(r.bestSession!.games, 3);
      expect(r.longestWinStreak, 2);
    },
  );

  test('excluded and casual games are left out', () {
    final r = splitRecap([
      ...games,
      buildMatch(
        start: t0 + 5 * 86400,
        rp: 500,
        cumulativeRp: 9999,
        excluded: true,
      ),
      buildMatch(start: t0 + 6 * 86400, rp: 0),
    ], metric: BestMetric.totalRp);

    expect(r.games, 6);
    expect(r.peakRp, 1050);
  });

  test('no games is an empty recap with nothing best', () {
    final r = splitRecap(const [], metric: BestMetric.totalRp);

    expect(r.isEmpty, isTrue);
    expect(r.bestLegend, isNull);
    expect(r.bestSession, isNull);
    expect(r.peakRp, 0);
  });

  test('win rate is wins over wins plus losses', () {
    final r = splitRecap(games, metric: BestMetric.totalRp);

    // Two wins and four losses.
    expect(r.winRate, closeTo(2 / 6, 1e-9));
  });

  test('a game that moved no RP is neither a win nor a loss', () {
    final r = splitRecap([
      buildMatch(start: t0, rp: 20, cumulativeRp: 1020),
      buildMatch(start: t0 + 1500, rp: 0, cumulativeRp: 1020),
    ], metric: BestMetric.totalRp);

    expect(r.winRate, 1);
  });

  test('win rate is unknown with no wins or losses', () {
    expect(splitRecap(const [], metric: BestMetric.totalRp).winRate, isNull);
    expect(
      splitRecap([
        buildMatch(start: t0, rp: 0, cumulativeRp: 1000),
      ], metric: BestMetric.totalRp).winRate,
      isNull,
    );
  });

  test('RP per game is the net over the games, and 0 with none', () {
    expect(
      splitRecap(games, metric: BestMetric.totalRp).avgRpPerGame,
      closeTo(-10 / 6, 1e-9),
    );
    expect(splitRecap(const [], metric: BestMetric.totalRp).avgRpPerGame, 0);
  });

  test('counts the games that reported kills', () {
    final r = splitRecap([
      buildMatch(start: t0, rp: 20, cumulativeRp: 1020, kills: 3),
      buildMatch(start: t0 + 1500, rp: 20, cumulativeRp: 1040),
    ], metric: BestMetric.totalRp);

    expect(r.killsGames, 1);
    expect(r.totalKills, 3);
    expect(
      splitRecap([
        buildMatch(start: t0, rp: 5),
      ], metric: BestMetric.totalRp).killsGames,
      0,
    );
  });

  test('totals the damage, and counts the games that reported it', () {
    final r = splitRecap([
      buildMatch(start: t0, rp: 20, cumulativeRp: 1020, damage: 500),
      buildMatch(start: t0 + 1500, rp: 20, cumulativeRp: 1040, damage: 700),
      buildMatch(start: t0 + 3000, rp: 20, cumulativeRp: 1060),
    ], metric: BestMetric.totalRp);

    expect(r.totalDamage, 1200);
    expect(r.damageGames, 2);
  });

  test('no game reporting damage leaves it unknown, not zero', () {
    final r = splitRecap([
      buildMatch(start: t0, rp: 5),
    ], metric: BestMetric.totalRp);

    expect(r.damageGames, 0);
  });
}
