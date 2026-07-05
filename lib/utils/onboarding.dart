import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/prefs_keys.dart';
import '../providers/navigation_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/onboarding/onboarding_screen.dart';

/// Current orientation-tour revision. Bump this when the tour changes enough to
/// re-show it to existing users as a "what's new" pass — [showOnboardingIfNeeded]
/// compares it against the stored [PrefsKeys.onboardingVersion].
const int kOnboardingVersion = 1;

/// Shows the orientation tour on first launch (or after [kOnboardingVersion] is
/// bumped). Marks it seen, then drops the user on My Stats so setting up an
/// account is the next thing they see.
Future<void> showOnboardingIfNeeded(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  final seen = prefs.getInt(PrefsKeys.onboardingVersion) ?? 0;
  if (seen >= kOnboardingVersion) return;
  if (!context.mounted) return;

  final navigator = Navigator.of(context);
  await navigator.push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => OnboardingScreen(
        onDone: () async {
          await prefs.setInt(PrefsKeys.onboardingVersion, kOnboardingVersion);
          navigator.pop();
        },
      ),
    ),
  );

  // Land on My Stats so the profile-setup form is the first thing they reach.
  ref.read(currentTabProvider.notifier).setTab(AppTab.stats);
}

/// Replays the tour from Settings. Just pops when finished — no tab change, so
/// the user returns to the Settings screen they launched it from. The seen
/// flag is already at the current version, so it isn't rewritten.
Future<void> openOnboarding(BuildContext context) async {
  final navigator = Navigator.of(context);
  await navigator.push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => OnboardingScreen(onDone: () async => navigator.pop()),
    ),
  );
}
