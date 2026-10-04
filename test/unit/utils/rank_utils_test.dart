import 'dart:io';

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

  group('rankAssetPathByTier', () {
    test('returns the predator asset when isPredator is true', () {
      expect(rankAssetPathByTier(true, 0), 'assets/ranks/apex_predator.webp');
    });

    test('returns the ladder asset for an in-range tier', () {
      expect(rankAssetPathByTier(false, 0), kRankLadder[0].assetPath);
    });

    test('clamps an out-of-range tier instead of throwing', () {
      // kPredatorGoalIndex (99) is stored in prefs the same way real ladder
      // indices are, so a caller can pass it with isPredator: false.
      expect(
        rankAssetPathByTier(false, 99),
        kRankLadder[kRankLadder.length - 1].assetPath,
      );
      expect(rankAssetPathByTier(false, -1), kRankLadder[0].assetPath);
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

  group('rankAssetPathFromImageUrl', () {
    test('maps every division of a tier onto that tier\'s bundled badge', () {
      for (final n in [1, 2, 3, 4]) {
        expect(
          rankAssetPathFromImageUrl(
            'https://api.apexlegendsstatus.com/assets/ranks/platinum$n.png',
          ),
          'assets/ranks/platinum.webp',
        );
      }
      expect(
        rankAssetPathFromImageUrl('https://x.example/ranks/Diamond4.png'),
        'assets/ranks/diamond.webp',
      );
    });

    test('reads the legacy host the same way — only the file name matters', () {
      expect(
        rankAssetPathFromImageUrl(
          'https://api.mozambiquehe.re/assets/ranks/gold2.png',
        ),
        'assets/ranks/gold.webp',
      );
    });

    test('recognises the predator badge however it is spelled', () {
      for (final name in ['apex_predator.png', 'apexpredator.png', 'predator.png']) {
        expect(
          rankAssetPathFromImageUrl('https://x.example/ranks/$name'),
          'assets/ranks/apex_predator.webp',
          reason: name,
        );
      }
    });

    test('every path it returns is a real bundled badge', () {
      for (final tier in ['bronze', 'silver', 'gold', 'platinum', 'diamond', 'master']) {
        final path = rankAssetPathFromImageUrl('https://x.example/ranks/${tier}1.png')!;
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('is null for a tier with no bundled badge, or no usable URL', () {
      expect(rankAssetPathFromImageUrl('https://x.example/ranks/rookie2.png'), isNull);
      expect(rankAssetPathFromImageUrl(''), isNull);
      expect(rankAssetPathFromImageUrl('not a url'), isNull);
      expect(rankAssetPathFromImageUrl('https://x.example/'), isNull);
    });
  });
}
