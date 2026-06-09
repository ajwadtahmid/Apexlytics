import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/map_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/player_provider.dart';
import 'providers/predator_provider.dart';
import 'providers/server_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home/home_screen.dart';
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

class _AppShellState extends ConsumerState<_AppShell> {
  // Screens are const and static: no instances are recreated on rebuild.
  // IndexedStack keeps all screens alive, so each maintains state across tab changes.
  static const _screens = [
    HomeScreen(),
    StatsScreen(),
    SearchScreen(),
    SettingsScreen(),
  ];
  static const _kPhase2Delay = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    unawaited(Future(() {
      final defaultTab = ref.read(playerSettingsProvider).defaultTab;
      ref.read(currentTabProvider.notifier).setTab(defaultTab);
    }));

    ref.listenManual(playerSettingsProvider, (prev, next) {
      if (prev?.defaultTab != next.defaultTab) {
        // Defer the state update so it doesn't run in the middle of a build —
        // this listener fires synchronously during the build phase.
        Future(() => ref.read(currentTabProvider.notifier).setTab(next.defaultTab));
      }
    });
    unawaited(_runStartupSequence());
  }

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
    final currentTab = ref.watch(currentTabProvider);

    return Scaffold(
      body: IndexedStack(index: currentTab, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentTab,
        onTap: (i) => ref.read(currentTabProvider.notifier).setTab(i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'My Stats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
