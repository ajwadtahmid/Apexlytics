import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/map_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/player_provider.dart';
import 'providers/predator_provider.dart';
import 'providers/server_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/ranked_provider.dart';
import 'screens/home/home_screen.dart';
import 'screens/ranked/ranked_breakdown_view.dart';
import 'screens/search/search_screen.dart';
import 'screens/stats/stats_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'utils/app_logger.dart';
import 'utils/theme.dart';

class ApexLegendsApp extends StatelessWidget {
  const ApexLegendsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Apexlytics',
      theme: AppTheme.materialTheme,
      home: const _AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell>
    with WidgetsBindingObserver {
  static const _kPhase2Delay = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(Future(() {
      final defaultTab = ref.read(playerSettingsProvider).defaultTab;
      ref.read(currentTabProvider.notifier).setTab(appTabForDefault(defaultTab));
    }));

    ref.listenManual(playerSettingsProvider, (prev, next) {
      if (prev?.defaultTab != next.defaultTab) {
        // Defer the state update so it doesn't run in the middle of a build —
        // this listener fires synchronously during the build phase.
        Future(() => ref
            .read(currentTabProvider.notifier)
            .setTab(appTabForDefault(next.defaultTab)));
      }
    });
    unawaited(_runStartupSequence());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-validate the approved-UID allowlist on resume so a revoked/granted
      // UID flips the Ranked tab promptly.
      ref.read(approvedUidsProvider.notifier).refresh();
    }
  }

  Widget _screenFor(AppTab tab) {
    final screen = switch (tab) {
      AppTab.home => const HomeScreen(),
      AppTab.stats => const StatsScreen(),
      AppTab.ranked => RankedBreakdownView(
          // Owns its own Scaffold/AppBar (the AppBar hosts the split selector).
          uid: ref.watch(playerSettingsProvider.select((s) => s.uid)),
        ),
      AppTab.search => const SearchScreen(),
      AppTab.settings => const SettingsScreen(),
    };
    // Keyed so the IndexedStack preserves each screen's state even when Ranked
    // is inserted/removed and the others shift position.
    return KeyedSubtree(key: ValueKey(tab), child: screen);
  }

  BottomNavigationBarItem _navItemFor(AppTab tab) => switch (tab) {
    AppTab.home => const BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home),
        label: 'Home',
      ),
    AppTab.stats => const BottomNavigationBarItem(
        icon: Icon(Icons.bar_chart_outlined),
        activeIcon: Icon(Icons.bar_chart),
        label: 'My Stats',
      ),
    AppTab.ranked => const BottomNavigationBarItem(
        icon: Icon(Icons.leaderboard_outlined),
        activeIcon: Icon(Icons.leaderboard),
        label: 'Ranked',
      ),
    AppTab.search => const BottomNavigationBarItem(
        icon: Icon(Icons.search_outlined),
        activeIcon: Icon(Icons.search),
        label: 'Search',
      ),
    AppTab.settings => const BottomNavigationBarItem(
        icon: Icon(Icons.settings_outlined),
        activeIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
  };

  /// Fires API requests in priority order on launch:
  ///   Phase 1 — Map rotation + Seasonal maps + My Stats in parallel (highest priority)
  ///   Phase 2 — Predator cutoff + Server health (150 ms later)
  /// Favorites are NOT pre-fetched — only updated on manual sync.
  Future<void> _runStartupSequence() async {
    final settings = ref.read(playerSettingsProvider);

    unawaited(_prefetch(ref.read(mapRotationProvider.future)));
    unawaited(_prefetch(ref.read(seasonalMapsProvider.future)));
    if (settings.isPlayerSet) {
      unawaited(_prefetch(ref.read(myPlayerStatsProvider.future)));
    }

    // Phase 2: fire after a short yield so phase 1 gets its network slot first
    await Future.delayed(_kPhase2Delay);
    unawaited(_prefetch(ref.read(predatorProvider.future)));
    unawaited(_prefetch(ref.read(serverStatusProvider.future)));
  }

  Future<void> _prefetch(Future<Object?> future) async {
    try {
      await future;
    } catch (e) {
      log.i('Startup prefetch failed', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(visibleTabsProvider);
    final currentTab = ref.watch(currentTabProvider);

    // The selected tab may not be in the visible set (e.g. switched away from an
    // approved profile while on Ranked) — fall back to the first tab.
    var index = tabs.indexOf(currentTab);
    if (index < 0) index = 0;

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [for (final t in tabs) _screenFor(t)],
      ),
      bottomNavigationBar: BottomNavigationBar(
        // Fixed type keeps all labels visible once there are 5 items.
        type: BottomNavigationBarType.fixed,
        currentIndex: index,
        onTap: (i) => ref.read(currentTabProvider.notifier).setTab(tabs[i]),
        items: [for (final t in tabs) _navItemFor(t)],
      ),
    );
  }
}
