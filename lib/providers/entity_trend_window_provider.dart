import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/prefs_keys.dart';
import '../utils/ranked/entity_trend_window.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// How many of a legend's or map's newest games its trend lines count as
/// recent, as the player last chose it: a count (see [isTrendChoice]), or
/// [kEntityTrendAuto] to let each legend or map get a window to suit how much
/// it has been played. Kept between visits. A choice too big for one legend is
/// narrowed when it is used (see [resolveEntityTrendWindow]), not when it is
/// saved, so it applies again wherever there are games enough.
final entityTrendWindowProvider =
    NotifierProvider<EntityTrendWindowNotifier, int>(
      EntityTrendWindowNotifier.new,
    );

class EntityTrendWindowNotifier extends Notifier<int> {
  @override
  int build() {
    final saved = ref
        .read(sharedPreferencesProvider)
        .getInt(PrefsKeys.entityTrendGames);
    return saved != null && isTrendChoice(saved) ? saved : kEntityTrendAuto;
  }

  /// Picks [games] (or [kEntityTrendAuto]) and keeps it. A count that is not
  /// [isTrendChoice] is ignored, since it would only be dropped at the next
  /// launch.
  Future<void> set(int games) async {
    if (!isTrendChoice(games)) return;
    state = games;
    await ref
        .read(sharedPreferencesProvider)
        .setInt(PrefsKeys.entityTrendGames, games);
  }
}
