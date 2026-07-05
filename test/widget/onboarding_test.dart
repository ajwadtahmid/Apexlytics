import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexlytics/constants/prefs_keys.dart';
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
    testWidgets('walks through pages and calls onDone on Get started',
        (tester) async {
      var doneCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onDone: () async => doneCalls++),
        ),
      );

      // First page + Skip visible; last-page CTA not yet shown.
      expect(find.text('Welcome to Apexlytics'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);

      // Advance through all four pages.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Scout friends and rivals'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(doneCalls, 1);
    });

    testWidgets('Skip calls onDone', (tester) async {
      var doneCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onDone: () async => doneCalls++),
        ),
      );

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(doneCalls, 1);
    });

    testWidgets('shows the tracker tip on the second page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onDone: () async {})),
      );

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

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
      expect(find.text('See your progress'), findsOneWidget);

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

      // Finish the tour: three Next taps + Get started.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      // Tour dismissed and flag persisted at the current version.
      expect(find.text('Welcome to Apexlytics'), findsNothing);
      expect(prefs.getInt(PrefsKeys.onboardingVersion), kOnboardingVersion);
    });

    testWidgets('does not show when already seen at the current version',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.onboardingVersion: kOnboardingVersion,
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_wrap(prefs, const _GateHarness()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Apexlytics'), findsNothing);
    });
  });
}
