import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_breakdown_body.dart';
import 'package:apexlytics/services/games_service.dart' show GamesEligibility;

import '../helpers.dart';

/// Covers the empty-state outcome routing in `_emptyState()`
/// (ranked_breakdown_body.dart:180-265) — pure branching over provider state
/// that was entirely untested.
void main() {
  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.rankedInfoCoachMarkShown: true,
      ...values,
    });
    return SharedPreferences.getInstance();
  }

  Widget app({
    required SharedPreferences prefs,
    required RankedSyncOutcome outcome,
    GamesEligibility? eligibility,
  }) {
    const uid = 'uid123';
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rankedSplitsProvider(uid).overrideWith((ref) async => []),
        rankedSyncProvider(uid).overrideWith((ref) async => outcome),
        gamesEligibilityProvider(uid).overrideWith((ref) async => eligibility),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RankedBreakdownBody(
            uid: uid,
            stats: buildStats(uid: uid),
            rpDelta: null,
            snapshots: const [],
            allSeasons: const {},
            legendStats: const [],
            compactLegendCards: false,
            legendStack: const [],
            onRefresh: () async {},
          ),
        ),
      ),
    );
  }

  testWidgets('not tracked and not recording prompts to start recording', (
    tester,
  ) async {
    final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 0});
    await tester.pumpWidget(
      app(prefs: prefs, outcome: RankedSyncOutcome.notTracked),
    );
    await tester.pump();

    expect(find.text('Ready to record'), findsOneWidget);
    expect(find.text('Start recording'), findsOneWidget);
  });

  testWidgets('recording but ineligible shows the not-tracked-yet message', (
    tester,
  ) async {
    final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
    await tester.pumpWidget(
      app(
        prefs: prefs,
        outcome: RankedSyncOutcome.cooldown,
        eligibility: (eligible: false, lastPolledAt: null, pollCount: 0),
      ),
    );
    // gamesEligibilityProvider resolves one microtask after rankedSyncProvider
    // and rankedSplitsProvider, so `.value` needs an extra pump to stop
    // reading null (loading) and fall into the ineligible branch.
    await tester.pump();
    await tester.pump();

    expect(find.text('Not being tracked yet'), findsOneWidget);
  });

  testWidgets('queued outcome shows server busy', (tester) async {
    final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
    await tester.pumpWidget(
      app(
        prefs: prefs,
        outcome: RankedSyncOutcome.queued,
        eligibility: (eligible: true, lastPolledAt: null, pollCount: 5),
      ),
    );
    await tester.pump();

    expect(find.text('Server busy'), findsOneWidget);
  });

  testWidgets('offline outcome shows the offline message', (tester) async {
    final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
    await tester.pumpWidget(
      app(prefs: prefs, outcome: RankedSyncOutcome.offline),
    );
    await tester.pump();

    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('synced with nothing recorded yet shows warming up', (
    tester,
  ) async {
    final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
    await tester.pumpWidget(
      app(
        prefs: prefs,
        outcome: RankedSyncOutcome.synced,
        eligibility: (eligible: true, lastPolledAt: null, pollCount: 5),
      ),
    );
    await tester.pump();

    expect(find.text('Warming up'), findsOneWidget);
  });
}
