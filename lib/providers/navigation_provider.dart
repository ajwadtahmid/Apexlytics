import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stable tab identities. The app tracks the selected tab by identity, never by
/// raw index, so the stored `defaultTab` and navigation stay correct if the
/// visible set ever changes again in the future.
///
/// Each tab's name and stored `defaultTab` value live here only (the nav bar
/// and the Settings picker read them). A stored value is saved in settings and
/// backups: never renumber one.
enum AppTab {
  home('Home', 0, Icons.home_outlined, Icons.home),
  stats('Stats', 1, Icons.bar_chart_outlined, Icons.bar_chart),
  search('Search', 2, Icons.search_outlined, Icons.search),
  settings('Settings', 3, Icons.settings_outlined, Icons.settings);

  const AppTab(this.label, this.storedValue, this.icon, this.activeIcon);

  /// The nav bar icon, and the filled one while the tab is selected. The
  /// orientation tour shows the same one, so a slide matches its tab.
  final IconData icon;
  final IconData activeIcon;

  /// The name shown in the nav bar and in the "Default tab" picker.
  final String label;

  /// The `defaultTab` setting value that selects this tab.
  final int storedValue;
}

/// The ordered list of visible tabs. Ranked Breakdown is part of Stats
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

  /// A tap on [tab] in the nav bar. Tapping Stats while already on it also
  /// asks the page to go back to its first tab (see [statsReselectProvider]).
  void tapNav(AppTab tab) {
    if (tab == AppTab.stats && state == AppTab.stats) {
      ref.read(statsReselectProvider.notifier).bump();
    }
    state = tab;
  }
}

/// Counts taps on Stats in the nav bar while it is already showing. Stats
/// listens, and returns to its Overview tab on each one.
final statsReselectProvider = NotifierProvider<_StatsReselectNotifier, int>(
  _StatsReselectNotifier.new,
);

class _StatsReselectNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
