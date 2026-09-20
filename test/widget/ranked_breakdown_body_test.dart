import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/player_stats.dart' show LegendStat;
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_breakdown_body.dart';
import 'package:apexlytics/services/games_service.dart'
    show GamesCapacity, GamesEligibility;
import 'package:apexlytics/utils/formatting/snapshot_types.dart';

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
    GamesCapacity? capacity,
    List<StatSnapshot> snapshots = const [],
    List<LegendStat> legendStats = const [],
    Object? splitsError,
  }) {
    const uid = 'uid123';
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (splitsError != null)
          rankedSplitsProvider(
            uid,
          ).overrideWith((ref) async => throw splitsError)
        else
          rankedSplitsProvider(uid).overrideWith((ref) async => []),
        rankedSyncProvider(uid).overrideWith((ref) async => outcome),
        gamesEligibilityProvider(uid).overrideWith((ref) async => eligibility),
        gamesCapacityProvider.overrideWith((ref) async => capacity),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RankedBreakdownBody(
            uid: uid,
            stats: buildStats(uid: uid),
            rpDelta: null,
            snapshots: snapshots,
            allSeasons: const {},
            legendStats: legendStats,
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

  testWidgets(
    'queued outcome with a capacity snapshot shows the concrete slot count',
    (tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.queued,
          eligibility: (eligible: true, lastPolledAt: null, pollCount: 5),
          capacity: (
            maxPerHour: 15,
            used: 12,
            free: 3,
            windowResetsAt: DateTime.now().add(const Duration(minutes: 12)),
            waitlistDepth: 2,
            locked: false,
          ),
        ),
      );
      await tester.pump();
      // A second pump lets the overridden gamesCapacityProvider's Future
      // resolve — the first pump only gets as far as its loading state.
      await tester.pump();

      expect(
        find.textContaining('3 of 15 history slots free'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'queued outcome with a locked capacity snapshot says so, not just busy',
    (tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.queued,
          eligibility: (eligible: true, lastPolledAt: null, pollCount: 5),
          capacity: (
            maxPerHour: 15,
            used: 15,
            free: 0,
            windowResetsAt: DateTime.now().add(const Duration(minutes: 40)),
            waitlistDepth: 6,
            locked: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('paused briefly after a hiccup'),
        findsOneWidget,
      );
    },
  );

  testWidgets('offline outcome shows the offline message', (tester) async {
    final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
    await tester.pumpWidget(
      app(prefs: prefs, outcome: RankedSyncOutcome.offline),
    );
    await tester.pump();

    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets(
    'requestError outcome shows a distinct message from offline',
    (tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(prefs: prefs, outcome: RankedSyncOutcome.requestError),
      );
      await tester.pump();

      expect(find.text('Can\'t sync right now'), findsOneWidget);
      // Must not be misdiagnosed as a connectivity problem — that's the
      // whole point of the distinct outcome.
      expect(find.text('Offline'), findsNothing);
    },
  );

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

  testWidgets(
    'recording, eligible but paused (pollCount > 0) shows the paused message',
    (tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.cooldown,
          eligibility: (eligible: false, lastPolledAt: 123, pollCount: 5),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Distinct from the pollCount == 0 "hasn't seen this profile yet"
      // message - this player *was* being tracked and stopped.
      expect(find.text('Not being tracked yet'), findsOneWidget);
      expect(find.textContaining('Tracking has paused'), findsOneWidget);
    },
  );

  testWidgets(
    '"View available stats" is offered when snapshots exist, even with no '
    'match history',
    (tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.synced,
          eligibility: (eligible: true, lastPolledAt: null, pollCount: 5),
          snapshots: [StatSnapshot(timestamp: DateTime(2026, 1, 1), rp: 1200)],
        ),
      );
      await tester.pump();

      expect(find.text('View available stats'), findsOneWidget);
    },
  );

  testWidgets(
    '"View available stats" is offered when legend stats exist, even with '
    'no snapshots or match history',
    (tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.synced,
          eligibility: (eligible: true, lastPolledAt: null, pollCount: 5),
          legendStats: [buildLegend()],
        ),
      );
      await tester.pump();

      expect(find.text('View available stats'), findsOneWidget);
    },
  );

  testWidgets(
    '"View available stats" is absent with neither snapshots nor legend '
    'stats',
    (tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.synced,
          eligibility: (eligible: true, lastPolledAt: null, pollCount: 5),
        ),
      );
      await tester.pump();

      expect(find.text('View available stats'), findsNothing);
    },
  );

  testWidgets(
    'a failed rankedSplitsProvider (cold start, no persisted history) shows '
    'the error state, not a blank empty state',
    (tester) async {
      final prefs = await prefsWith({});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome:
              RankedSyncOutcome.offline, // irrelevant - splits errors first
          splitsError: Exception('cold start, no connection'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Can't load history"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );
}
