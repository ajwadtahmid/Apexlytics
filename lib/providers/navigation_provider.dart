import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stable tab identities. The app tracks the selected tab by identity, never by
/// raw index, so the stored `defaultTab` and navigation stay correct if the
/// visible set ever changes again in the future.
enum AppTab { home, stats, search, settings }

/// The ordered list of visible tabs. Ranked Breakdown is part of My Stats
/// (see `StatsScreen`), not a separate tab.
final visibleTabsProvider = Provider<List<AppTab>>((ref) {
  return const [AppTab.home, AppTab.stats, AppTab.search, AppTab.settings];
});

/// Maps the legacy `defaultTab` setting (0=Home 1=Stats 2=Search 3=Settings) to
/// a stable [AppTab].
AppTab appTabForDefault(int defaultTab) => switch (defaultTab) {
  1 => AppTab.stats,
  2 => AppTab.search,
  3 => AppTab.settings,
  _ => AppTab.home,
};

final currentTabProvider = NotifierProvider<_CurrentTabNotifier, AppTab>(
  _CurrentTabNotifier.new,
);

class _CurrentTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void setTab(AppTab tab) => state = tab;
}
