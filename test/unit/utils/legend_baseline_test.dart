import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/ranked/legend_baseline.dart';

void main() {
  var n = 0;
  RankedMatch game({
    String legend = 'Axle',
    int rp = 10,
    int? kills = 2,
    int? damage = 500,
    bool excluded = false,
  }) {
    final start = 1782090000 + (n++) * 1000;
    final m = RankedMatch.fromJson({
      'uid': '1',
      'name': 'Tester',
      'legendPlayed': legend,
      'gameMode': 'BATTLE_ROYALE',
      'gameLengthSecs': 600,
      'gameStartTimestamp': start,
      'gameEndTimestamp': start + 600,
      'gameData': [
        if (kills != null) {'key': 'kills', 'value': kills, 'name': 'BR Kills'},
        if (damage != null)
          {'key': 'damage', 'value': damage, 'name': 'BR Damage'},
      ],
      'BRScoreChange': rp,
      'BRScore': 1000,
      'map': 'olympus_rotation',
      'isPartyFull': false,
    });
    return excluded ? m.withExcluded(true) : m;
  }

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

    test('ignores other legends, excluded and outlier games', () {
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
