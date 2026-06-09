import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/constants/rank_constants.dart';
import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/utils/formatting/rank_utils.dart';

PlayerStats _stubStats({required String rank, required int rankScore}) =>
    PlayerStats(
      name: 'Test',
      uid: '1',
      level: 1,
      rank: rank,
      rankScore: rankScore,
      platform: 'PC',
      currentLegend: 'Wraith',
      isOnline: false,
      isInGame: false,
      trackers: [],
    );

void main() {
  group('rankIndex', () {
    test('returns 0 for 0 RP (Rookie IV)', () => expect(rankIndex(0), 0));
    test('returns correct index for Bronze IV threshold', () {
      final idx = rankIndex(1000);
      expect(kRankLadder[idx].tier, 'Bronze');
    });
    test('clamps below minimum to 0', () => expect(rankIndex(-1), 0));
    test('returns last index for very high RP', () {
      final idx = rankIndex(999999);
      expect(idx, kRankLadder.length - 1);
    });
  });

  group('rankLabel', () {
    test('returns kApexPredatorRank string for predator rank', () {
      final stats = _stubStats(rank: kApexPredatorRank, rankScore: 20000);
      expect(rankLabel(stats), kApexPredatorRank);
    });

    test('returns ladder label for non-predator', () {
      final stats = _stubStats(rank: 'Gold', rankScore: 5500);
      expect(rankLabel(stats), contains('Gold'));
    });

    test('non-predator label matches kRankLadder entry', () {
      final stats = _stubStats(rank: 'Silver', rankScore: 3000);
      final expected = kRankLadder[rankIndex(3000)].label;
      expect(rankLabel(stats), expected);
    });
  });

  group('rankColor', () {
    test('predator returns kPredatorColor', () {
      final stats = _stubStats(rank: kApexPredatorRank, rankScore: 20000);
      expect(rankColor(stats).toARGB32(), kPredatorColor.toARGB32());
    });

    test('non-predator returns ladder color', () {
      final stats = _stubStats(rank: 'Gold', rankScore: 5500);
      final expected = kRankLadder[rankIndex(5500)].color;
      expect(rankColor(stats).toARGB32(), expected.toARGB32());
    });
  });

  group('RankDivision.label', () {
    test('includes division for tiered ranks', () {
      expect(kRankLadder[0].label, 'Rookie IV');
    });
    test('omits division for Master', () {
      final master = kRankLadder.firstWhere((r) => r.tier == 'Master');
      expect(master.label, 'Master');
    });
  });
}
