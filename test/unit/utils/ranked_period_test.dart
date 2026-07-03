import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/utils/formatting/season_utils.dart';
import 'package:apexlytics/utils/ranked/ranked_period.dart';

void main() {
  // Split A (older): [1.0M, 2.0M).  Split B (newer): [2.0M, 3.0M).
  final seasons = {
    'br_ranked_s28_s2': SeasonMeta.fromApi(
        id: 'br_ranked_s28_s2', startSeconds: 1000000, endSeconds: 2000000),
    'br_ranked_s29_s1': SeasonMeta.fromApi(
        id: 'br_ranked_s29_s1', startSeconds: 2000000, endSeconds: 3000000),
  };

  // Splits are read from the persisted [RankedMatch.seasonId], not
  // re-derived live — mirror what RankedHistoryStore.upsertAll would have
  // stamped on write, using the same [seasonIdForEndTime] it uses.
  RankedMatch m(int startSecs, {int rp = 10}) {
    final base = RankedMatch.fromJson({
      'uid': '1',
      'name': 'T',
      'legendPlayed': 'Axle',
      'gameMode': 'BATTLE_ROYALE',
      'gameLengthSecs': 600,
      'gameStartTimestamp': startSecs,
      'gameEndTimestamp': startSecs + 600,
      'gameData': [
        {'key': 'kills', 'value': 1, 'name': 'BR Kills'},
      ],
      'BRScoreChange': rp,
      'BRScore': 1000,
      'map': 'olympus_rotation',
    });
    return RankedMatch(
      uid: base.uid,
      playerName: base.playerName,
      legend: base.legend,
      gameMode: base.gameMode,
      mapKey: base.mapKey,
      rpChange: base.rpChange,
      cumulativeRp: base.cumulativeRp,
      rankImg: base.rankImg,
      lengthSecs: base.lengthSecs,
      startTime: base.startTime,
      endTime: base.endTime,
      isPartyFull: base.isPartyFull,
      trackers: base.trackers,
      seasonId: seasonIdForEndTime(base.endTime, seasons.values),
    );
  }

  // m1 in A; m2 in B week 1; m3 in B week 2; m4 before any split (Unknown).
  final matches = [m(1500000), m(2100000), m(2700000), m(500000)];

  group('splitBuckets', () {
    test('groups by split newest-first with Unknown appended last', () {
      final buckets = splitBuckets(matches, seasons);
      expect(buckets.length, 3);
      expect(buckets.first.id, 'br_ranked_s29_s1'); // newest = current
      expect(buckets[1].id, 'br_ranked_s28_s2');
      expect(buckets.last.id, kUnknownSplitId);
      expect(buckets.last.displayName, 'Unknown');
      expect(buckets.last.season, isNull);
    });

    test('groups by the persisted seasonId, not a live date recheck', () {
      // Stamped under s29_s1 at write time even though its own end time (in
      // split A's window) would now derive differently — grouping must
      // follow the stored id, since a real classification is never allowed
      // to be second-guessed live.
      final relabeled = RankedMatch(
        uid: '1',
        playerName: 'T',
        legend: 'Axle',
        gameMode: 'BATTLE_ROYALE',
        mapKey: 'olympus_rotation',
        rpChange: 10,
        cumulativeRp: 1000,
        rankImg: '',
        lengthSecs: 600,
        startTime: DateTime.fromMillisecondsSinceEpoch(1500000000, isUtc: true),
        endTime: DateTime.fromMillisecondsSinceEpoch(1500600000, isUtc: true),
        isPartyFull: false,
        trackers: const [],
        seasonId: 'br_ranked_s29_s1',
      );
      final buckets = splitBuckets([relabeled], seasons);
      expect(buckets.single.id, 'br_ranked_s29_s1');
    });

    test('falls back to the raw id when season metadata is missing', () {
      final unknownMeta = RankedMatch(
        uid: '1',
        playerName: 'T',
        legend: 'Axle',
        gameMode: 'BATTLE_ROYALE',
        mapKey: 'olympus_rotation',
        rpChange: 10,
        cumulativeRp: 1000,
        rankImg: '',
        lengthSecs: 600,
        startTime: DateTime.fromMillisecondsSinceEpoch(2100000000, isUtc: true),
        endTime: DateTime.fromMillisecondsSinceEpoch(2100600000, isUtc: true),
        isPartyFull: false,
        trackers: const [],
        seasonId: 'br_ranked_s30_s1',
      );
      final buckets = splitBuckets([unknownMeta], const {});
      expect(buckets.single.id, 'br_ranked_s30_s1');
      expect(buckets.single.displayName, 'br_ranked_s30_s1');
      expect(buckets.single.season, isNull);
    });
  });

  group('resolveRankedView', () {
    test('defaults to current split, all weeks', () {
      final view = resolveRankedView(matches, seasons);
      expect(view.effectiveSplitId, 'br_ranked_s29_s1');
      expect(view.weekIndex, -1);
      expect(view.filtered.length, 2); // m2 + m3 (both in split B)
      expect(view.weeks.length, 2); // ~11.5 days → 2 weeks
    });

    test('filters by week within the split', () {
      final w0 = resolveRankedView(matches, seasons,
          splitId: 'br_ranked_s29_s1', weekIndex: 0);
      expect(w0.filtered.length, 1); // m2 only

      final w1 = resolveRankedView(matches, seasons,
          splitId: 'br_ranked_s29_s1', weekIndex: 1);
      expect(w1.filtered.length, 1); // m3 only
    });

    test('selecting an older split scopes to its matches', () {
      final view =
          resolveRankedView(matches, seasons, splitId: 'br_ranked_s28_s2');
      expect(view.filtered.length, 1); // m1
    });

    test('Unknown bucket holds matches outside every known split', () {
      final view = resolveRankedView(matches, seasons, splitId: kUnknownSplitId);
      expect(view.filtered.length, 1); // m4
      expect(view.weeks, isEmpty); // no week navigation for Unknown
    });

    test('invalid split id falls back to current split', () {
      final view = resolveRankedView(matches, seasons, splitId: 'nonexistent');
      expect(view.effectiveSplitId, 'br_ranked_s29_s1');
    });

    test('out-of-range week falls back to All', () {
      final view = resolveRankedView(matches, seasons,
          splitId: 'br_ranked_s29_s1', weekIndex: 99);
      expect(view.weekIndex, -1);
      expect(view.filtered.length, 2);
    });

    test('no matches yields the empty view', () {
      expect(resolveRankedView(const [], seasons).isEmpty, true);
    });

    test('History keeps pubs (0 RP) but aggregates exclude them', () {
      final data = [
        m(2100000), // ranked in split B
        m(2700000, rp: 0), // pub in split B (no RP change)
      ];
      final view = resolveRankedView(data, seasons);
      expect(view.effectiveSplitId, 'br_ranked_s29_s1');
      expect(view.filtered.length, 1); // ranked only
      expect(view.history.length, 2); // pub kept in history
    });
  });
}
