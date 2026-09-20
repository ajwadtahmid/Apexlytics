import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/rank_goal_provider.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';

/// invalidatePlayerDerivedProviders takes a WidgetRef (it's called from
/// widget code), so exercising it needs a real widget tree rather than a bare
/// ProviderContainer.
void main() {
  const uid = 'uid123';

  testWidgets('invalidatePlayerDerivedProviders resets rankGoalProvider', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.rankGoalKeyFor(uid): 5});
    final prefs = await SharedPreferences.getInstance();

    late WidgetRef capturedRef;
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              container = ProviderScope.containerOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(container.read(rankGoalProvider(uid)), 5);

    // Mirrors clearAll()/backup-import changing the pref out from under
    // an already-built provider instance.
    await prefs.remove(PrefsKeys.rankGoalKeyFor(uid));
    invalidatePlayerDerivedProviders(capturedRef);

    expect(
      container.read(rankGoalProvider(uid)),
      isNull,
      reason:
          'a stale in-memory goal must not keep being served once the '
          'backing pref is cleared or replaced',
    );
  });
}
