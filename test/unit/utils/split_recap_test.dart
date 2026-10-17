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
    final r = splitRecap(games);

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
    final r = splitRecap(games);

    expect(r.bestLegend!.legend, 'Axle');
    expect(r.bestMap!.displayName, 'Olympus');
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
    ]);

    expect(r.bestLegend!.legend, 'Axle');
  });

  test(
    'best session gained the most RP, and the streak counts wins in a row',
    () {
      final r = splitRecap(games);

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
    ]);

    expect(r.games, 6);
    expect(r.peakRp, 1050);
  });

  test('no games is an empty recap with nothing best', () {
    final r = splitRecap(const []);

    expect(r.isEmpty, isTrue);
    expect(r.bestLegend, isNull);
    expect(r.bestSession, isNull);
    expect(r.peakRp, 0);
  });
}
