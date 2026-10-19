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
  group('Apex Predator rules', () {
    final masterFloor = kRankLadder.last.rp;

    test('a cutoff below the Master floor is no cutoff', () {
      // Missing parses to 0; a negative value is a "no data" placeholder.
      for (final bad in [null, 0, -1, 500, masterFloor - 1]) {
        expect(usablePredatorCutoff(bad), isNull, reason: '$bad');
      }
      expect(usablePredatorCutoff(masterFloor), masterFloor);
      expect(usablePredatorCutoff(17500), 17500);
    });

    test('nobody below Master is Predator, whatever the cutoff', () {
      expect(isApexPredatorRp(5600, 0), isFalse);
      expect(isApexPredatorRp(5600, 500), isFalse);
      expect(isApexPredatorRp(masterFloor - 1, masterFloor), isFalse);
    });

    test('Master and above need to reach the cutoff', () {
      expect(isApexPredatorRp(17000, 17500), isFalse);
      expect(isApexPredatorRp(17500, 17500), isTrue);
      expect(isApexPredatorRp(20000, 17500), isTrue);
    });

    test('no usable cutoff means nobody is promoted to Predator', () {
      expect(isApexPredatorRp(50000, null), isFalse);
      expect(isApexPredatorRp(50000, 0), isFalse);
    });
  });

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

  group('rank badge assets', () {
    test('every ladder rung either has its badge on disk or none at all', () {
      for (final d in kRankLadder) {
        final path = d.assetPath;
        if (path != null) {
          expect(
            File(path).existsSync(),
            isTrue,
            reason: '$path for ${d.label}',
          );
        }
      }
      expect(File(kPredatorBadgeAsset).existsSync(), isTrue);
    });

    test('each rung shows its own division, and Master its single badge', () {
      final gold2 = kRankLadder.firstWhere(
        (d) => d.tier == 'Gold' && d.division == 'II',
      );
      expect(gold2.assetPath, 'assets/ranks/gold_2.webp');
      final master = kRankLadder.firstWhere((d) => d.tier == 'Master');
      expect(master.assetPath, 'assets/ranks/master.webp');
      // Every division of every tier is a different, real file.
      final paths = [
        for (final d in kRankLadder)
          if (d.assetPath != null) d.assetPath,
      ];
      expect(paths.toSet().length, paths.length);
    });

    test('a division badge is picked only for tiers that have them', () {
      expect(rankBadgePath('master', division: 2), 'assets/ranks/master.webp');
      expect(rankBadgePath('rookie', division: 2), isNull);
      expect(
        rankBadgePath('diamond', division: 5),
        'assets/ranks/diamond.webp',
      );
    });

    test('Rookie has no badge, and nothing else is missing one', () {
      for (final d in kRankLadder) {
        expect(d.assetPath == null, d.tier == 'Rookie', reason: d.label);
      }
    });

    test('the helpers agree: no art is null, Predator is its own badge', () {
      expect(rankAssetPathByTier(false, 0), isNull);
      expect(rankAssetPathByTier(true, 0), kPredatorBadgeAsset);
      expect(
        rankAssetPathByTier(false, kRankLadder.length - 1),
        'assets/ranks/master.webp',
      );
    });
  });

  group('rankDisplayColor', () {
    final gold = kRankLadder[rankIndex(5500)];

    test('Predator is shown in the Predator colour', () {
      expect(
        rankDisplayColor(gold, isPredator: true).toARGB32(),
        kPredatorColor.toARGB32(),
      );
    });

    test('any other rank is shown in its own division colour', () {
      expect(rankDisplayColor(gold).toARGB32(), gold.color.toARGB32());
    });

    test('every rung of the ladder resolves to its colour', () {
      for (final d in kRankLadder) {
        expect(rankDisplayColor(d), d.color);
      }
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
    test('maps each division of a tier onto that division\'s badge', () {
      for (final n in [1, 2, 3, 4]) {
        expect(
          rankAssetPathFromImageUrl(
            'https://api.apexlegendsstatus.com/assets/ranks/platinum$n.png',
          ),
          'assets/ranks/platinum_$n.webp',
        );
      }
      expect(
        rankAssetPathFromImageUrl('https://x.example/ranks/Diamond4.png'),
        'assets/ranks/diamond_4.webp',
      );
    });

    test('Master has no divisions, so any number gives its one badge', () {
      for (final name in ['master', 'master1', 'master4']) {
        expect(
          rankAssetPathFromImageUrl('https://x.example/ranks/$name.png'),
          'assets/ranks/master.webp',
          reason: name,
        );
      }
    });

    test('a missing or out-of-range division gives the plain tier badge', () {
      for (final name in ['gold', 'gold0', 'gold5', 'gold12']) {
        expect(
          rankAssetPathFromImageUrl('https://x.example/ranks/$name.png'),
          'assets/ranks/gold.webp',
          reason: name,
        );
      }
    });

    test('reads the legacy host the same way — only the file name matters', () {
      expect(
        rankAssetPathFromImageUrl(
          'https://api.mozambiquehe.re/assets/ranks/gold2.png',
        ),
        'assets/ranks/gold_2.webp',
      );
    });

    test('recognises the predator badge however it is spelled', () {
      for (final name in [
        'apex_predator.png',
        'apexpredator.png',
        'predator.png',
      ]) {
        expect(
          rankAssetPathFromImageUrl('https://x.example/ranks/$name'),
          'assets/ranks/apex_predator.webp',
          reason: name,
        );
      }
    });

    test('every path it returns is a real bundled badge', () {
      for (final tier in [
        'bronze',
        'silver',
        'gold',
        'platinum',
        'diamond',
        'master',
      ]) {
        for (final n in [1, 2, 3, 4]) {
          final path = rankAssetPathFromImageUrl(
            'https://x.example/ranks/$tier$n.png',
          )!;
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
    });

    test('is null for a tier with no bundled badge, or no usable URL', () {
      expect(
        rankAssetPathFromImageUrl('https://x.example/ranks/rookie2.png'),
        isNull,
      );
      expect(rankAssetPathFromImageUrl(''), isNull);
      expect(rankAssetPathFromImageUrl('not a url'), isNull);
      expect(rankAssetPathFromImageUrl('https://x.example/'), isNull);
    });
  });
}
