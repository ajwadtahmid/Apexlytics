import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/utils/ranked/ranked_period.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uid = 'uid123';
  const splitId = 'br_ranked_s29_s1';
  const day = 24 * 60 * 60;
  const splitStart = 1782000000; // arbitrary fixed epoch (seconds)

  final season = SeasonMeta.fromApi(
    id: splitId,
    startSeconds: splitStart,
    endSeconds: splitStart + 28 * day,
  );

  RankedMatch match(int startSecs, {required int cumulativeRp}) =>
      RankedMatch.fromJson({
        'uid': uid,
        'name': 'Tester',
        'legendPlayed': 'Axle',
        'gameMode': 'BATTLE_ROYALE',
        'gameLengthSecs': 600,
        'gameStartTimestamp': startSecs,
        'gameEndTimestamp': startSecs + 600,
        'gameData': const [],
        'BRScoreChange': 10,
        'BRScore': cumulativeRp,
        'map': 'olympus_rotation',
      });

  // Week 1 ends at 1000 RP, week 2 at 1500 RP.
  final week1 = match(splitStart + day, cumulativeRp: 1000);
  final week2 = match(splitStart + 8 * day, cumulativeRp: 1500);

  ProviderContainer containerWith(List<RankedMatch> matches) {
    final container = ProviderContainer(
      overrides: [
        rankedSplitsProvider.overrideWith(
          (ref, _) async => [
            RankedSplitBucket(
              id: splitId,
              displayName: 'S29 Split 1',
              season: season,
            ),
          ],
        ),
        rankedSplitMatchesProvider.overrideWith((ref, _) async => matches),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the whole split\'s current RP is kept when a past week is picked',
      () async {
    final container = containerWith([week2, week1]);
    container.read(rankedPeriodProvider.notifier).selectWeek(0);

    final view = await container.read(
      rankedSplitViewProvider((uid: uid, splitId: splitId)).future,
    );

    // The stats are week 1's, but "current" RP is where the split stands now.
    expect(view.summary.games, 1);
    expect(view.summary.currentRp, 1500);
  });

  test('with every week selected, current RP is the newest game\'s', () async {
    final container = containerWith([week2, week1]);

    final view = await container.read(
      rankedSplitViewProvider((uid: uid, splitId: splitId)).future,
    );

    expect(view.summary.games, 2);
    expect(view.summary.currentRp, 1500);
  });
}
