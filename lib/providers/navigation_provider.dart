import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stable tab identities. The app tracks the selected tab by identity, never by
/// raw index, so the stored `defaultTab` and navigation stay correct if the
/// visible set ever changes again in the future.
///
/// Each tab's name and stored `defaultTab` value live here only (the nav bar
/// and the Settings picker read them). A stored value is saved in settings and
/// backups: never renumber one.
enum AppTab {
  home('Home', 0),
  stats('My Stats', 1),
  search('Search', 2),
  settings('Settings', 3);

  const AppTab(this.label, this.storedValue);

  /// The name shown in the nav bar and in the "Default tab" picker.
  final String label;

  /// The `defaultTab` setting value that selects this tab.
  final int storedValue;
}

/// The ordered list of visible tabs. Ranked Breakdown is part of My Stats
/// (see `StatsScreen`), not a separate tab.
final visibleTabsProvider = Provider<List<AppTab>>((ref) {
  return const [AppTab.home, AppTab.stats, AppTab.search, AppTab.settings];
});

/// Maps the stored `defaultTab` setting to a stable [AppTab] (see
/// [AppTab.storedValue]); an unknown value is Home.
AppTab appTabForDefault(int defaultTab) => AppTab.values.firstWhere(
  (t) => t.storedValue == defaultTab,
  orElse: () => AppTab.home,
);

final currentTabProvider = NotifierProvider<_CurrentTabNotifier, AppTab>(
  _CurrentTabNotifier.new,
);

class _CurrentTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void setTab(AppTab tab) => state = tab;
}
