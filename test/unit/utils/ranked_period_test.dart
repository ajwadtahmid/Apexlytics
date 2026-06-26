import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/utils/ranked/ranked_period.dart';

void main() {
  // Split A (older): [1.0M, 2.0M).  Split B (newer): [2.0M, 3.0M).
  final seasons = {
    'br_ranked_s28_s2': SeasonMeta.fromApi(
        id: 'br_ranked_s28_s2', startSeconds: 1000000, endSeconds: 2000000),
    'br_ranked_s29_s1': SeasonMeta.fromApi(
        id: 'br_ranked_s29_s1', startSeconds: 2000000, endSeconds: 3000000),
  };

  RankedMatch m(int startSecs, {int rp = 10}) => RankedMatch.fromJson({
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

  // m1 in A; m2 in B week 1; m3 in B week 2; m4 before any split (Other).
  final matches = [m(1500000), m(2100000), m(2700000), m(500000)];

  group('splitBuckets', () {
    test('groups by split newest-first with Other appended last', () {
      final buckets = splitBuckets(matches, seasons);
      expect(buckets.length, 3);
      expect(buckets.first.id, 'br_ranked_s29_s1'); // newest = current
      expect(buckets[1].id, 'br_ranked_s28_s2');
      expect(buckets.last.id, kOtherSplitId);
      expect(buckets.last.season, isNull);
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

    test('Other bucket holds matches outside every known split', () {
      final view = resolveRankedView(matches, seasons, splitId: kOtherSplitId);
      expect(view.filtered.length, 1); // m4
      expect(view.weeks, isEmpty); // no week navigation for Other
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
