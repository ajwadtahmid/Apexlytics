import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/utils/ranked/ranked_period.dart';

void main() {
  // Split A (older): [1.0M, 2.0M).  Split B (newer): [2.0M, 3.0M).
  final seasons = {
    'br_ranked_s28_s2': SeasonMeta.fromApi(
      id: 'br_ranked_s28_s2',
      startSeconds: 1000000,
      endSeconds: 2000000,
    ),
    'br_ranked_s29_s1': SeasonMeta.fromApi(
      id: 'br_ranked_s29_s1',
      startSeconds: 2000000,
      endSeconds: 3000000,
    ),
  };

  // A plain match — the split picker now comes from counts, and
  // resolveRankedView takes matches already scoped to one split, so only
  // isRanked (rp != 0) and endTime (for week slicing) matter here.
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

  group('buildSplitBuckets', () {
    test('Lifetime first, newest split next, Unknown last', () {
      final buckets = buildSplitBuckets({
        'br_ranked_s28_s2': 1,
        'br_ranked_s29_s1': 2,
        kUnknownSplitId: 1,
      }, seasons);
      expect(buckets.length, 4);
      expect(buckets[0].id, kLifetimeSplitId);
      expect(buckets[0].displayName, 'Lifetime');
      expect(buckets[0].season, isNull);
      expect(buckets[1].id, 'br_ranked_s29_s1'); // newest = current
      expect(buckets[1].displayName, 'Season 29 (Split 1)');
      expect(buckets[2].id, 'br_ranked_s28_s2');
      expect(buckets.last.id, kUnknownSplitId);
      expect(buckets.last.displayName, 'Unknown');
      expect(buckets.last.season, isNull);
    });

    test('no Lifetime bucket when only one split exists', () {
      final buckets = buildSplitBuckets({'br_ranked_s29_s1': 3}, seasons);
      expect(buckets.map((b) => b.id), ['br_ranked_s29_s1']);
    });

    test('Lifetime appears once a split + Unknown both have games', () {
      final buckets = buildSplitBuckets({
        'br_ranked_s29_s1': 3,
        kUnknownSplitId: 2,
      }, seasons);
      expect(buckets.first.id, kLifetimeSplitId);
      expect(buckets.length, 3); // Lifetime + split + Unknown
    });

    test('excludes zero-count splits', () {
      final buckets = buildSplitBuckets({
        'br_ranked_s29_s1': 0,
        'br_ranked_s28_s2': 3,
      }, seasons);
      expect(buckets.map((b) => b.id), ['br_ranked_s28_s2']);
    });

    test('falls back to the raw id when metadata is missing', () {
      final buckets = buildSplitBuckets({'br_ranked_s30_s1': 2}, const {});
      expect(buckets.single.id, 'br_ranked_s30_s1');
      expect(buckets.single.displayName, 'br_ranked_s30_s1');
      expect(buckets.single.season, isNull);
    });

    test('empty counts yield no buckets', () {
      expect(buildSplitBuckets(const {}, seasons), isEmpty);
    });
  });

  group('effectiveSplitId', () {
    // [Lifetime, s29_s1, s28_s2]
    final splits = buildSplitBuckets({
      'br_ranked_s29_s1': 1,
      'br_ranked_s28_s2': 1,
    }, seasons);

    test('returns the selection when it is a real split', () {
      expect(effectiveSplitId(splits, 'br_ranked_s28_s2'), 'br_ranked_s28_s2');
    });
    test('Lifetime is selectable but never the default', () {
      // Explicitly selected → honoured.
      expect(effectiveSplitId(splits, kLifetimeSplitId), kLifetimeSplitId);
      // Default (null) skips Lifetime for the newest real split, even though
      // Lifetime is splits.first.
      expect(effectiveSplitId(splits, null), 'br_ranked_s29_s1');
      expect(effectiveSplitId(splits, 'nope'), 'br_ranked_s29_s1');
    });
    test('empty splits resolve to empty string', () {
      expect(effectiveSplitId(const [], 'x'), '');
    });
    test('isLifetimeSplit', () {
      expect(isLifetimeSplit(kLifetimeSplitId), true);
      expect(isLifetimeSplit('br_ranked_s29_s1'), false);
      expect(isLifetimeSplit(null), false);
    });
  });

  group('weeksForBucket', () {
    test('a real split divides into weeks', () {
      final b = buildSplitBuckets({'br_ranked_s29_s1': 1}, seasons).single;
      expect(weeksForBucket(b).length, 2); // ~11.5 days → 2 weeks
    });
    test('the Unknown bucket has no weeks', () {
      final b = buildSplitBuckets({kUnknownSplitId: 1}, seasons).single;
      expect(weeksForBucket(b), isEmpty);
    });
    test('Lifetime has no weeks', () {
      final buckets = buildSplitBuckets({
        'br_ranked_s29_s1': 1,
        'br_ranked_s28_s2': 1,
      }, seasons);
      final b = buckets.firstWhere((b) => b.id == kLifetimeSplitId);
      expect(weeksForBucket(b), isEmpty);
    });
  });

  group('resolveRankedView', () {
    final splits = buildSplitBuckets({
      'br_ranked_s29_s1': 2,
      'br_ranked_s28_s2': 1,
    }, seasons);
    // Matches already scoped to split B (as getBySeason would return them).
    final splitB = [m(2100000), m(2700000)]; // week 0, week 1

    test('defaults to the current split, all weeks', () {
      final view = resolveRankedView(splits: splits, splitMatches: splitB);
      expect(view.effectiveSplitId, 'br_ranked_s29_s1');
      expect(view.weekIndex, -1);
      expect(view.filtered.length, 2);
      expect(view.weeks.length, 2);
    });

    test('filters by week within the split', () {
      final w0 = resolveRankedView(
        splits: splits,
        splitMatches: splitB,
        selectedSplitId: 'br_ranked_s29_s1',
        weekIndex: 0,
      );
      expect(w0.filtered.length, 1);

      final w1 = resolveRankedView(
        splits: splits,
        splitMatches: splitB,
        selectedSplitId: 'br_ranked_s29_s1',
        weekIndex: 1,
      );
      expect(w1.filtered.length, 1);
    });

    test('keeps pubs (0 RP) in history but excludes them from aggregates', () {
      final data = [m(2100000), m(2700000, rp: 0)];
      final view = resolveRankedView(
        splits: splits,
        splitMatches: data,
        selectedSplitId: 'br_ranked_s29_s1',
      );
      expect(view.filtered.length, 1); // ranked only
      expect(view.history.length, 2); // pub kept in history
    });

    test('an invalid split id falls back to the current split', () {
      final view = resolveRankedView(
        splits: splits,
        splitMatches: splitB,
        selectedSplitId: 'nonexistent',
      );
      expect(view.effectiveSplitId, 'br_ranked_s29_s1');
    });

    test('an out-of-range week falls back to All', () {
      final view = resolveRankedView(
        splits: splits,
        splitMatches: splitB,
        selectedSplitId: 'br_ranked_s29_s1',
        weekIndex: 99,
      );
      expect(view.weekIndex, -1);
      expect(view.filtered.length, 2);
    });

    test('the Unknown split has no week navigation', () {
      final s = buildSplitBuckets({kUnknownSplitId: 1}, seasons);
      final view = resolveRankedView(
        splits: s,
        splitMatches: [m(500000)],
        selectedSplitId: kUnknownSplitId,
      );
      expect(view.filtered.length, 1);
      expect(view.weeks, isEmpty);
    });

    test('no splits yields the empty view', () {
      expect(
        resolveRankedView(splits: const [], splitMatches: const []).isEmpty,
        true,
      );
    });
  });
}
