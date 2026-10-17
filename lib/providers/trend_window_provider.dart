import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/prefs_keys.dart';
import '../utils/ranked/performance_insights.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// How many of the latest sessions the Performance Trends page looks at, as the
/// player last chose it: one of [kTrendWindowPresets], or [kTrendWindowAll].
/// Kept between visits. A choice too big for the sessions on screen is
/// narrowed when it is used (see [resolveTrendWindow]), not when it is saved,
/// so it applies again when there are enough sessions.
final trendWindowProvider = NotifierProvider<TrendWindowNotifier, int>(
  TrendWindowNotifier.new,
);

class TrendWindowNotifier extends Notifier<int> {
  @override
  int build() {
    final saved = ref
        .read(sharedPreferencesProvider)
        .getInt(PrefsKeys.trendSessionsShown);
    final known =
        saved == kTrendWindowAll ||
        (saved != null && kTrendWindowPresets.contains(saved));
    return known ? saved! : kDefaultTrendWindow;
  }

  /// Picks [window] and keeps it.
  Future<void> set(int window) async {
    state = window;
    await ref
        .read(sharedPreferencesProvider)
        .setInt(PrefsKeys.trendSessionsShown, window);
  }
}
