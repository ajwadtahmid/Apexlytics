import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/navigation_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/onboarding/onboarding_screen.dart';
import 'package:apexlytics/utils/onboarding.dart';

/// Drives [showOnboardingIfNeeded] from a mounted route so the gate has a real
/// Navigator and BuildContext to push over.
class _GateHarness extends ConsumerStatefulWidget {
  const _GateHarness();

  @override
  ConsumerState<_GateHarness> createState() => _GateHarnessState();
}

class _GateHarnessState extends ConsumerState<_GateHarness> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showOnboardingIfNeeded(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('shell'));
}

Widget _wrap(SharedPreferences prefs, Widget child) {
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('OnboardingScreen', () {
    testWidgets('walks through pages and calls onDone on Get started', (
      tester,
    ) async {
      var doneCalls = 0;
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onDone: () async => doneCalls++)),
      );

      // First page + Skip visible; last-page CTA not yet shown.
      expect(find.text('Welcome to Apexlytics'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);

      // Advance to the last page. Driven by the CTA rather than a hard-coded
      // page count, so adding a page doesn't break this test — the bound is
      // just a guard against an infinite loop if Next ever stops advancing.
      for (var i = 0; i < 20 && find.text('Next').evaluate().isNotEmpty; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Make it yours'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(doneCalls, 1);
    });

    testWidgets('every slide fits a small phone without overflowing, and its '
        'text can be reached', (tester) async {
      // 360x616 body is what a 360x640 phone leaves under the header.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: OnboardingScreen(onDone: () async {}),
          ),
        ),
      );

      for (var i = 0; i < 20; i++) {
        expect(tester.takeException(), isNull, reason: 'slide $i');
        if (find.text('Next').evaluate().isEmpty) break;
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      // The last slide's small print is reachable by scrolling.
      expect(find.text('Get started'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('promises the profile limit the app enforces', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onDone: () async {})),
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(
        find.textContaining(
          'Save up to ${PlayerSettingsNotifier.maxProfileCount} profiles',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Skip calls onDone', (tester) async {
      var doneCalls = 0;
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onDone: () async => doneCalls++)),
      );

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(doneCalls, 1);
    });

    testWidgets('shows the tracker tip on the setup page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onDone: () async {})),
      );

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('Apex Kills and Apex Damage'), findsOneWidget);
    });

    testWidgets('back button is hidden on the first page and returns to the '
        'previous page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onDone: () async {})),
      );

      // Hidden (disabled) on the first page.
      final backButton = find.widgetWithIcon(IconButton, Icons.arrow_back);
      expect(tester.widget<IconButton>(backButton).onPressed, isNull);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text("Know where you're dropping"), findsOneWidget);

      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Apexlytics'), findsOneWidget);
    });
  });

  group('showOnboardingIfNeeded', () {
    testWidgets('shows the tour and marks it seen when unseen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_wrap(prefs, const _GateHarness()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Apexlytics'), findsOneWidget);

      // Finish the tour. Page count is deliberately not hard-coded here.
      for (var i = 0; i < 20 && find.text('Next').evaluate().isNotEmpty; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Set up my profile'));
      await tester.pumpAndSettle();

      // Tour dismissed and flag persisted at the current version.
      expect(find.text('Welcome to Apexlytics'), findsNothing);
      expect(prefs.getInt(PrefsKeys.onboardingVersion), kOnboardingVersion);
    });

    testWidgets('leaving with back counts as seen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_wrap(prefs, const _GateHarness()));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Apexlytics'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Apexlytics'), findsNothing);
      expect(prefs.getInt(PrefsKeys.onboardingVersion), kOnboardingVersion);
    });

    testWidgets('does not show when already seen at the current version', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.onboardingVersion: kOnboardingVersion,
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_wrap(prefs, const _GateHarness()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Apexlytics'), findsNothing);
    });
  });
  group('the slides', () {
    Future<void> open(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onDone: () async {})),
    );

    Future<void> next(WidgetTester tester, [int times = 1]) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }

    const titles = [
      'Welcome to Apexlytics',
      "Know where you're dropping",
      'Set up your player',
      'How recording works',
      'Your ranked history',
      'The four tabs, one split',
      'Scout friends and rivals',
      'Make it yours',
    ];

    testWidgets('run Welcome, Home, setup, recording, ranked, tabs, Search, '
        'Settings', (tester) async {
      await open(tester);

      for (var i = 0; i < titles.length; i++) {
        expect(find.text(titles[i]), findsOneWidget, reason: 'slide $i');
        if (i < titles.length - 1) await next(tester);
      }
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('a slide about a tab names it and wears its icon', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining(' TAB'), findsNothing); // Welcome

      await next(tester); // Home
      expect(find.text('HOME TAB'), findsOneWidget);
      expect(find.byIcon(AppTab.home.activeIcon), findsOneWidget);

      await next(tester); // Set up your player
      expect(find.text('STATS TAB'), findsOneWidget);
      expect(find.byIcon(AppTab.stats.activeIcon), findsOneWidget);

      await next(tester); // How recording works: about no one tab
      expect(find.textContaining(' TAB'), findsNothing);

      await next(tester); // Your ranked history: lives on Overview
      expect(find.text('STATS TAB · OVERVIEW'), findsOneWidget);

      await next(tester); // The four tabs
      expect(find.text('STATS TAB'), findsOneWidget);

      await next(tester); // Search
      expect(find.text('SEARCH TAB'), findsOneWidget);
      expect(find.byIcon(AppTab.search.activeIcon), findsOneWidget);

      await next(tester); // Settings
      expect(find.text('SETTINGS TAB'), findsOneWidget);
      expect(find.byIcon(AppTab.settings.activeIcon), findsOneWidget);
    });

    testWidgets('Home points at the bell and the cutoff for your platform', (
      tester,
    ) async {
      await open(tester);
      await next(tester);

      expect(find.textContaining('Tap the bell on the map'), findsOneWidget);
      expect(
        find.textContaining('Pred cutoff for your platform'),
        findsOneWidget,
      );
    });

    testWidgets('setup says how, that Switch needs a UID, and what comes '
        'next', (tester) async {
      await open(tester);
      await next(tester, 2);

      expect(find.textContaining('by name or UID'), findsOneWidget);
      expect(
        find.textContaining('Switch needs a UID'),
        findsOneWidget,
      );
      expect(find.text('Equip your trackers'), findsOneWidget);
      expect(
        find.textContaining('Apex Kills and Apex Damage'),
        findsOneWidget,
      );
      expect(find.text('Then watch your RP climb'), findsOneWidget);
      expect(
        find.textContaining('every ranked game, across the split'),
        findsOneWidget,
      );
      expect(
        find.text('It starts empty and fills in as you play ranked.'),
        findsOneWidget,
      );
    });

    testWidgets('the trackers are a point, not a tip, and come before the '
        'RP climb', (tester) async {
      await open(tester);
      await next(tester, 2);

      expect(find.textContaining('Tip:'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Equip your trackers')).dy,
        lessThan(tester.getTopLeft(find.text('Then watch your RP climb')).dy),
      );
    });

    testWidgets('the empty-at-first line closes setup, and recording is '
        'next', (tester) async {
      await open(tester);
      await next(tester, 2);
      expect(
        find.text('It starts empty and fills in as you play ranked.'),
        findsOneWidget,
      );

      await next(tester);
      expect(find.text('How recording works'), findsOneWidget);
      expect(
        find.text('It starts empty and fills in as you play ranked.'),
        findsNothing,
      );
    });

    testWidgets('ranked history pairs each tile with the question it answers', (
      tester,
    ) async {
      await open(tester);
      await next(tester, 4);

      for (final (label, question) in const [
        ('Legend × Map, Pick Rate', 'Which legends and maps earn me RP?'),
        ('Performance Trends', 'When do I play best?'),
        ('Sessions', 'How did each night go?'),
        ('Compare', 'How does this split stack up against another?'),
        ('Recap, Records', 'What can I share, and what is my best?'),
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
        expect(find.text(question), findsOneWidget, reason: question);
        // The tile name above its question.
        expect(
          tester.getTopLeft(find.text(label)).dy,
          lessThan(tester.getTopLeft(find.text(question)).dy),
        );
      }
      expect(
        find.textContaining('Once games are recorded, tiles under the RP chart'),
        findsOneWidget,
      );
    });

    testWidgets('the four tabs are named as the page names them', (
      tester,
    ) async {
      await open(tester);
      await next(tester, 5);

      expect(
        find.text('Pick a split and week at the top, and everything follows it.'),
        findsOneWidget,
      );
      for (final tab in ['Overview', 'Legends', 'Maps', 'Games']) {
        expect(find.text(tab), findsOneWidget, reason: tab);
      }
      expect(find.text('History'), findsNothing);
    });

    testWidgets('recording says what it needs, that it cannot look back, and '
        'where the backup is', (tester) async {
      await open(tester);
      await next(tester, 3);

      expect(find.text('How recording works'), findsOneWidget);
      expect(
        find.textContaining('only while your profile is tracked'),
        findsOneWidget,
      );
      expect(find.textContaining("can't be recovered"), findsOneWidget);
      expect(
        find.textContaining(
          'lives only on this device. Export a backup in Settings under Data',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Search says name or UID, and how to keep favorites', (
      tester,
    ) async {
      await open(tester);
      await next(tester, 6);

      expect(find.textContaining('by name or UID'), findsOneWidget);
      expect(find.textContaining('swipe one away'), findsOneWidget);
    });

    testWidgets('the last button says what it was given', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(finishLabel: 'Done', onDone: () async {}),
        ),
      );
      await next(tester, titles.length - 1);

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
    });

    testWidgets('the back arrow and the dots are labelled for a screen '
        'reader', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);

      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 1 of 8'), findsOneWidget);
      await next(tester);
      expect(find.bySemanticsLabel('Page 2 of 8'), findsOneWidget);
      handle.dispose();
    });
  });

  group('after the tour', () {
    Future<ProviderContainer> finishFirstRun(
      WidgetTester tester, {
      required bool withProfile,
    }) async {
      SharedPreferences.setMockInitialValues({
        if (withProfile) PrefsKeys.playerName: 'Aceu',
        if (withProfile) PrefsKeys.playerUid: '1006838015507',
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(_wrap(prefs, const _GateHarness()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingScreen)),
      );
      container.read(currentTabProvider.notifier).setTab(AppTab.home);
      for (var i = 0; i < 20 && find.text('Next').evaluate().isNotEmpty; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      return container;
    }

    testWidgets('with no player, offers to set one up and lands on Stats', (
      tester,
    ) async {
      final container = await finishFirstRun(tester, withProfile: false);

      await tester.tap(find.text('Set up my profile'));
      await tester.pumpAndSettle();

      expect(container.read(currentTabProvider), AppTab.stats);
    });

    testWidgets('with a player, just says Done and stays where it was', (
      tester,
    ) async {
      final container = await finishFirstRun(tester, withProfile: true);
      expect(find.text('Set up my profile'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(container.read(currentTabProvider), AppTab.home);
    });
  });

  group('the version', () {
    test('is 3, so earlier tours are shown again as a what is new', () {
      expect(kOnboardingVersion, 3);
    });

    testWidgets('someone who saw version 2 gets the tour again', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({PrefsKeys.onboardingVersion: 2});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_wrap(prefs, const _GateHarness()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Apexlytics'), findsOneWidget);
    });
  });
}
