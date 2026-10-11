import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/prefs_keys.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// Whose goal, in which split. [newestSplit] marks the split in progress, which
/// is the one a goal saved before goals were kept per split belongs to.
typedef RankGoalScope = ({String uid, String splitId, bool newestSplit});

/// The player's ranked goal — an index into `kRankLadder` they're climbing
/// toward — scoped per UID and split, so a goal set in one split doesn't show
/// in another. Null means no goal set (the progress card then tracks the next
/// division automatically).
final rankGoalProvider =
    NotifierProvider.family<RankGoalNotifier, int?, RankGoalScope>(
      RankGoalNotifier.new,
    );

class RankGoalNotifier extends Notifier<int?> {
  RankGoalNotifier(this.scope);

  final RankGoalScope scope;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  String get _key => PrefsKeys.rankGoalKeyForSplit(scope.uid, scope.splitId);

  /// What older versions stored for the player as a whole. Read as the newest
  /// split's goal until that split gets one of its own.
  String get _legacyKey => PrefsKeys.rankGoalKeyFor(scope.uid);

  @override
  int? build() {
    return _prefs.getInt(_key) ??
        (scope.newestSplit ? _prefs.getInt(_legacyKey) : null);
  }

  /// Sets (or clears, when [ladderIndex] is null) the goal and persists it.
  Future<void> setGoal(int? ladderIndex) async {
    if (ladderIndex == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setInt(_key, ladderIndex);
    }
    // The newest split's goal now lives under its own key; leaving the old one
    // would bring a cleared goal back.
    if (scope.newestSplit) await _prefs.remove(_legacyKey);
    state = ladderIndex;
  }
}
