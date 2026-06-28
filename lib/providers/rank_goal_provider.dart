import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/prefs_keys.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// The player's ranked goal — an index into `kRankLadder` they're climbing
/// toward — scoped per UID. Null means no goal set (the progress card then
/// tracks the next division automatically).
final rankGoalProvider =
    NotifierProvider.family<RankGoalNotifier, int?, String>(
  RankGoalNotifier.new,
);

class RankGoalNotifier extends Notifier<int?> {
  RankGoalNotifier(this.uid);

  final String uid;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  int? build() {
    final v = _prefs.getInt(PrefsKeys.rankGoalKeyFor(uid));
    return v;
  }

  /// Sets (or clears, when [ladderIndex] is null) the goal and persists it.
  Future<void> setGoal(int? ladderIndex) async {
    final key = PrefsKeys.rankGoalKeyFor(uid);
    if (ladderIndex == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setInt(key, ladderIndex);
    }
    state = ladderIndex;
  }
}
