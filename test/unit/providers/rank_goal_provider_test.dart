import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/rank_goal_provider.dart';
import 'package:apexlytics/utils/storage/backup_service.dart' show backupIncludesKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  const uid = '1006838015507';
  const newest = 'br_ranked_s30_s2';
  const earlier = 'br_ranked_s30_s1';

  RankGoalScope inSplit(String id, {bool isNewest = false}) =>
      (uid: uid, splitId: id, newestSplit: isNewest);

  Future<(ProviderContainer, SharedPreferences)> setUp(
    Map<String, Object> values,
  ) => prefsContainer(values: values);

  test('a goal set in one split does not show in another', () async {
    final (c, _) = await setUp({});

    await c
        .read(rankGoalProvider(inSplit(newest, isNewest: true)).notifier)
        .setGoal(5);

    expect(c.read(rankGoalProvider(inSplit(newest, isNewest: true))), 5);
    expect(c.read(rankGoalProvider(inSplit(earlier))), isNull);
  });

  test('each split keeps its own goal', () async {
    final (c, _) = await setUp({});

    await c.read(rankGoalProvider(inSplit(earlier)).notifier).setGoal(3);
    await c
        .read(rankGoalProvider(inSplit(newest, isNewest: true)).notifier)
        .setGoal(6);

    expect(c.read(rankGoalProvider(inSplit(earlier))), 3);
    expect(c.read(rankGoalProvider(inSplit(newest, isNewest: true))), 6);
  });

  test('a goal saved before goals were per split belongs to the newest split',
      () async {
    final (c, _) = await setUp({PrefsKeys.rankGoalKeyFor(uid): 7});

    expect(c.read(rankGoalProvider(inSplit(newest, isNewest: true))), 7);
    expect(c.read(rankGoalProvider(inSplit(earlier))), isNull);
  });

  test('saving moves the old goal, and clearing it does not bring it back',
      () async {
    final (c, prefs) = await setUp({PrefsKeys.rankGoalKeyFor(uid): 7});
    final scope = inSplit(newest, isNewest: true);

    await c.read(rankGoalProvider(scope).notifier).setGoal(8);
    expect(prefs.getInt(PrefsKeys.rankGoalKeyFor(uid)), isNull);
    expect(prefs.getInt(PrefsKeys.rankGoalKeyForSplit(uid, newest)), 8);

    await c.read(rankGoalProvider(scope).notifier).setGoal(null);
    c.invalidate(rankGoalProvider);
    expect(c.read(rankGoalProvider(scope)), isNull);
  });

  test('setting a goal in an earlier split leaves the old goal for the newest',
      () async {
    final (c, prefs) = await setUp({PrefsKeys.rankGoalKeyFor(uid): 7});

    await c.read(rankGoalProvider(inSplit(earlier)).notifier).setGoal(2);

    expect(prefs.getInt(PrefsKeys.rankGoalKeyFor(uid)), 7);
    expect(c.read(rankGoalProvider(inSplit(newest, isNewest: true))), 7);
  });

  test('per-split goals are included in backups', () {
    expect(backupIncludesKey(PrefsKeys.rankGoalKeyForSplit(uid, newest)), isTrue);
  });
}
