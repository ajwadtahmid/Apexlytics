import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/ranked/legend_baseline.dart';

import '../../helpers.dart';

void main() {
  var n = 0;
  RankedMatch game({
    String legend = 'Axle',
    int rp = 10,
    int? kills = 2,
    int? damage = 500,
    bool excluded = false,
  }) => buildMatch(
    start: 1782090000 + (n++) * 1000,
    legend: legend,
    rp: rp,
    kills: kills,
    damage: damage,
    excluded: excluded,
  );

  group('legendBaselineFor', () {
    test('null below the minimum number of games', () {
      final pool = [for (var i = 0; i < 4; i++) game()];
      expect(legendBaselineFor(pool.first, pool), isNull);
    });

    test('averages kills and damage once there are enough games', () {
      final pool = [
        for (var i = 0; i < 5; i++) game(kills: i + 1, damage: (i + 1) * 100),
      ];
      final b = legendBaselineFor(pool.first, pool)!;
      expect(b.avgKills, 3);
      expect(b.avgDamage, 300);
    });

    test('pools spelling variants of one legend, as the aggregates do', () {
      final pool = [
        for (var i = 0; i < 3; i++) game(legend: 'Bloodhound', kills: 4),
        for (var i = 0; i < 2; i++) game(legend: 'bloodhound', kills: 4),
      ];

      // Five games between them, so the baseline exists for either spelling.
      expect(legendBaselineFor(pool.first, pool)!.avgKills, 4);
      expect(legendBaselineFor(pool.last, pool)!.avgKills, 4);
    });

    test('ignores other legends, excluded and auto-excluded games', () {
      final pool = [
        for (var i = 0; i < 5; i++) game(kills: 4),
        game(legend: 'Wraith', kills: 40),
        game(kills: 40, excluded: true),
        game(kills: 40, rp: 5000),
      ];
      expect(legendBaselineFor(pool.first, pool)!.avgKills, 4);
    });

    test('a stat with too few reports is dropped on its own', () {
      final pool = [
        for (var i = 0; i < 5; i++) game(damage: i < 2 ? 800 : null),
      ];
      final b = legendBaselineFor(pool.first, pool)!;
      expect(b.avgKills, 2);
      expect(b.avgDamage, isNull);
    });
  });
}
