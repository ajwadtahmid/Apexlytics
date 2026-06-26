import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ranked_provider.dart';

/// Stable tab identities. The visible set (and therefore each tab's *position*)
/// varies — Ranked only appears for approved UIDs — so the app tracks the
/// selected tab by identity, never by raw index. This keeps the stored
/// `defaultTab` and navigation correct regardless of whether Ranked is present.
enum AppTab { home, stats, ranked, search, settings }

/// The ordered list of tabs currently visible. Ranked sits between My Stats and
/// Search, and only for an approved active profile.
final visibleTabsProvider = Provider<List<AppTab>>((ref) {
  final rankedVisible = ref.watch(activeUidApprovedProvider);
  return [
    AppTab.home,
    AppTab.stats,
    if (rankedVisible) AppTab.ranked,
    AppTab.search,
    AppTab.settings,
  ];
});

/// Maps the legacy `defaultTab` setting (0=Home 1=Stats 2=Search 3=Settings) to
/// a stable [AppTab]. Ranked is intentionally not a selectable default.
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
