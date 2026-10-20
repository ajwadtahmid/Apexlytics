import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/player_stats.dart'
    show LegendStat, PlayerStats;
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/providers/navigation_provider.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_breakdown_body.dart';
import 'package:apexlytics/services/games_service.dart'
    show GamesCapacity, GamesEligibility;
import 'package:apexlytics/utils/formatting/snapshot_types.dart';
import 'package:apexlytics/utils/ranked/ranked_period.dart';

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

  /// A minimal ranked match, just enough to give a split a non-zero
  /// [RankedSummary.currentRp] via [RankedMatch.cumulativeRp].
  RankedMatch matchWith({required String uid, required int cumulativeRp}) =>
      buildMatch(
        uid: uid,
        start: 1700000000,
        legend: 'Wraith',
        rp: 40,
        cumulativeRp: cumulativeRp,
      );

  Widget app({
    required SharedPreferences prefs,
    required RankedSyncOutcome outcome,
    GamesEligibility? eligibility,
    GamesCapacity? capacity,
    List<StatSnapshot> snapshots = const [],
    List<LegendStat> legendStats = const [],
    Object? splitsError,
    PlayerStats? stats,
    List<RankedSplitBucket>? splits,
    List<RankedMatch>? splitMatches,
    void Function()? onSyncRun,
  }) {
    const uid = 'uid123';
    // A single bucket with no user selection always resolves to itself (see
    // effectiveSplitId), so every populated-view test below can override
    // both providers for this one fixed key.
    const splitId = 'br_ranked_s29_s1';
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (splitsError != null)
          rankedSplitsProvider(
            uid,
          ).overrideWith((ref) async => throw splitsError)
        else
          rankedSplitsProvider(uid).overrideWith((ref) async => splits ?? []),
        if (splits != null)
          rankedSplitMatchesProvider((
            uid: uid,
            splitId: splitId,
          )).overrideWith((ref) async => splitMatches ?? []),
        rankedSyncProvider(uid).overrideWith((ref) async {
          onSyncRun?.call();
          return outcome;
        }),
        gamesEligibilityProvider(uid).overrideWith((ref) async => eligibility),
        gamesCapacityProvider.overrideWith((ref) async => capacity),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RankedBreakdownBody(
            uid: uid,
            stats: stats ?? buildStats(uid: uid),
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

  group('the view\'s 10-minute sync timer', () {
    Future<int> syncRunsAfterTenMinutes(
      WidgetTester tester,
      int statsRefreshMinutes,
    ) async {
      final prefs = await prefsWith({
        PrefsKeys.statsRefreshMinutes: statsRefreshMinutes,
      });
      var runs = 0;
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.synced,
          onSyncRun: () => runs++,
        ),
      );
      await tester.pump();
      expect(runs, 1, reason: 'the initial sync');

      await tester.pump(const Duration(minutes: 10));
      await tester.pump();
      return runs;
    }

    testWidgets('leaves the sync to Stats\' timer when a refresh interval '
        'is set, instead of firing a second request', (tester) async {
      expect(await syncRunsAfterTenMinutes(tester, 10), 1);
    });

    testWidgets('is the retry when no refresh interval is set', (tester) async {
      expect(await syncRunsAfterTenMinutes(tester, 0), 2);
    });
  });

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
        eligibility: (eligible: false, pollCount: 0),
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
        eligibility: (eligible: true, pollCount: 5),
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
          eligibility: (eligible: true, pollCount: 5),
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
          eligibility: (eligible: true, pollCount: 5),
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

  testWidgets(
    'busy outcome says the server is pacing syncs for a moment, and never '
    'quotes a slot count that would contradict it',
    (tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.busy,
          eligibility: (eligible: true, pollCount: 5),
          // Slots are free, which is exactly why "N free, resets in M min"
          // would be wrong here.
          capacity: (
            maxPerHour: 15,
            used: 2,
            free: 13,
            windowResetsAt: DateTime.now().add(const Duration(minutes: 40)),
            waitlistDepth: 0,
            locked: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Busy for a moment'), findsOneWidget);
      // The card cannot be pulled, so it must not say to pull down.
      expect(find.textContaining('tap Retry'), findsOneWidget);
      expect(find.textContaining('pull down'), findsNothing);
      expect(find.textContaining('pacing new syncs'), findsOneWidget);
      expect(find.text('Server busy'), findsNothing);
      expect(find.textContaining('history slots free'), findsNothing);
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
        eligibility: (eligible: true, pollCount: 5),
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
          eligibility: (eligible: false, pollCount: 5),
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

  testWidgets('recording, with the server unable to say, shows neutral wording', (
    tester,
  ) async {
    final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
    await tester.pumpWidget(
      app(
        prefs: prefs,
        outcome: RankedSyncOutcome.cooldown,
        eligibility: (eligible: false, pollCount: null),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining("can't confirm"), findsOneWidget);
    expect(find.textContaining("hasn't seen"), findsNothing);
    expect(find.textContaining('Tracking has paused'), findsNothing);
  });

  testWidgets(
    '"View available stats" is offered when snapshots exist, even with no '
    'match history',
    (tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.synced,
          eligibility: (eligible: true, pollCount: 5),
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
          eligibility: (eligible: true, pollCount: 5),
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
          eligibility: (eligible: true, pollCount: 5),
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

  group('the "not synced" badge only compares live RP against the current split', () {
    const uid = 'uid123';
    // The only bucket, so it's on screen by default in both tests below.
    // "old" relative to the second test's live split (numbered later).
    const splitId = 'br_ranked_s29_s1';
    const liveSplitId = 'br_ranked_s30_s1';

    testWidgets(
      'shows when the split on screen is the live current split and its '
      'RP disagrees with the match history',
      (tester) async {
        final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
        await tester.pumpWidget(
          app(
            prefs: prefs,
            outcome: RankedSyncOutcome.synced,
            splits: const [
              RankedSplitBucket(id: splitId, displayName: 'S29 Split 1'),
            ],
            splitMatches: [matchWith(uid: uid, cumulativeRp: 1000)],
            stats: buildStats(
              uid: uid,
              rankScore: 1200, // hasn't synced into history yet
              rankedSeason: SeasonMeta.fromApi(
                id: splitId, // the split on screen IS the live one
                startSeconds: 0,
                endSeconds: 1000000,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.sync), findsOneWidget);
      },
    );

    testWidgets(
      'stays hidden on an old split even though its final RP disagrees '
      'with the live RP',
      (tester) async {
        final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
        await tester.pumpWidget(
          app(
            prefs: prefs,
            outcome: RankedSyncOutcome.synced,
            splits: const [
              RankedSplitBucket(id: splitId, displayName: 'S29 Split 1'),
            ],
            splitMatches: [matchWith(uid: uid, cumulativeRp: 1000)],
            stats: buildStats(
              uid: uid,
              rankScore: 1200, // the player's *current* RP, a new split away
              rankedSeason: SeasonMeta.fromApi(
                id: liveSplitId, // a later split is the live one, not splitId
                startSeconds: 0,
                endSeconds: 1000000,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.sync), findsNothing);
      },
    );
  });
  group('the Highlights header', () {
    const uid = 'uid123';
    const splitId = 'br_ranked_s29_s1';

    Future<void> showOverview(
      WidgetTester tester, {
      Map<String, Object> saved = const {},
    }) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await prefsWith({
        PrefsKeys.statsRefreshMinutes: 10,
        ...saved,
      });
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.synced,
          splits: const [
            RankedSplitBucket(id: splitId, displayName: 'S29 Split 1'),
          ],
          splitMatches: [
            for (var i = 0; i < 4; i++)
              buildMatch(
                uid: uid,
                start: 1700000000 + i * 1500,
                legend: 'Wraith',
                rp: 40,
                cumulativeRp: 1000 + i * 40,
              ),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('has the "Rank by" pill, on Total RP until changed', (
      tester,
    ) async {
      await showOverview(tester);

      expect(find.text('Highlights'), findsOneWidget);
      expect(find.text('Rank by:'), findsOneWidget);
      expect(find.text('Total RP'), findsOneWidget);
      expect(find.text('+160 RP'), findsWidgets); // the legend card's pill
    });

    testWidgets('shows what was chosen, on the cards too', (tester) async {
      await showOverview(tester, saved: {PrefsKeys.bestMetric: 'rpPerGame'});

      expect(find.text('Avg RP'), findsWidgets); // the pill, and the stat
      expect(find.text('+40.0 /game'), findsWidgets);
      // Total RP is back down in the stats, no longer the card's pill.
      expect(find.text('TOTAL RP'), findsWidgets);
    });
  });

  group('tapping Stats in the nav bar while on it', () {
    const uid = 'uid123';
    const splitId = 'br_ranked_s29_s1';

    Future<ProviderContainer> showSplit(WidgetTester tester) async {
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.synced,
          splits: const [
            RankedSplitBucket(id: splitId, displayName: 'S29 Split 1'),
          ],
          splitMatches: [matchWith(uid: uid, cumulativeRp: 1000)],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RankedBreakdownBody)),
      );
      container.read(currentTabProvider.notifier).setTab(AppTab.stats);
      return container;
    }

    bool selected(WidgetTester tester, String label) {
      final index = ['Overview', 'Legends', 'Maps', 'Games'].indexOf(label);
      return DefaultTabController.of(
            tester.element(find.byType(TabBar)),
          ).index ==
          index;
    }

    for (final tab in ['Legends', 'Maps', 'Games']) {
      testWidgets('returns to Overview from $tab', (tester) async {
        final container = await showSplit(tester);
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(selected(tester, tab), isTrue);

        container.read(currentTabProvider.notifier).tapNav(AppTab.stats);
        await tester.pumpAndSettle();

        expect(selected(tester, 'Overview'), isTrue);
      });
    }

    testWidgets('does not move you when you arrive from another tab', (
      tester,
    ) async {
      final container = await showSplit(tester);
      await tester.tap(find.text('Maps'));
      await tester.pumpAndSettle();
      container.read(currentTabProvider.notifier).setTab(AppTab.home);

      container.read(currentTabProvider.notifier).tapNav(AppTab.stats);
      await tester.pumpAndSettle();

      expect(selected(tester, 'Maps'), isTrue);
      expect(container.read(currentTabProvider), AppTab.stats);
    });

    testWidgets('leaves Overview where it is', (tester) async {
      final container = await showSplit(tester);

      container.read(currentTabProvider.notifier).tapNav(AppTab.stats);
      await tester.pumpAndSettle();

      expect(selected(tester, 'Overview'), isTrue);
    });
  });
  group('the Overview headings', () {
    const uid = 'uid123';
    const splitId = 'br_ranked_s29_s1';

    Future<void> showOverview(WidgetTester tester) async {
      // Tall enough that the whole list is built.
      tester.view.physicalSize = const Size(800, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 10});
      await tester.pumpWidget(
        app(
          prefs: prefs,
          outcome: RankedSyncOutcome.synced,
          splits: const [
            RankedSplitBucket(id: splitId, displayName: 'S29 Split 1'),
          ],
          splitMatches: [matchWith(uid: uid, cumulativeRp: 1000)],
        ),
      );
      await tester.pumpAndSettle();
    }

    double top(WidgetTester tester, String label) =>
        tester.getTopLeft(find.text(label)).dy;

    testWidgets('split the page into account, split, highlights and tools, '
        'in that order', (tester) async {
      await showOverview(tester);

      final tops = [
        for (final h in ['Your account', 'This split', 'Highlights', 'Dig deeper'])
          top(tester, h),
      ];

      expect(tops, [...tops]..sort());
      expect(tops.toSet(), hasLength(4));
    });

    testWidgets('put the tiles under Dig deeper, and the RP chart under the '
        'split heading', (tester) async {
      await showOverview(tester);

      for (final tile in ['Sessions', 'Compare', 'Recap']) {
        expect(
          top(tester, tile),
          greaterThan(top(tester, 'Dig deeper')),
          reason: tile,
        );
      }
      expect(top(tester, 'This split'), lessThan(top(tester, 'Highlights')));
      expect(find.text('This week'), findsNothing);
    });

    testWidgets('are on Overview only', (tester) async {
      await showOverview(tester);

      await tester.tap(find.text('Legends'));
      await tester.pumpAndSettle();

      expect(find.text('Your account'), findsNothing);
      expect(find.text('Dig deeper'), findsNothing);
    });
  });
  group('the first-run state', () {
    const preview = 'WHAT YOU WILL SEE HERE';

    Future<void> showEmpty(
      WidgetTester tester, {
      required RankedSyncOutcome outcome,
      int refreshMinutes = 10,
      GamesEligibility? eligibility = (eligible: true, pollCount: 5),
    }) async {
      final prefs = await prefsWith({
        PrefsKeys.statsRefreshMinutes: refreshMinutes,
      });
      await tester.pumpWidget(
        app(prefs: prefs, outcome: outcome, eligibility: eligibility),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('previews the page while waiting for a first game', (
      tester,
    ) async {
      await showEmpty(tester, outcome: RankedSyncOutcome.synced);

      expect(find.text('Warming up'), findsOneWidget);
      expect(find.text(preview), findsOneWidget);
      expect(find.text('RP this split'), findsOneWidget);
      expect(find.text('Win rate'), findsOneWidget);
    });

    testWidgets('previews it before recording has started', (tester) async {
      await showEmpty(
        tester,
        outcome: RankedSyncOutcome.notTracked,
        refreshMinutes: 0,
      );

      expect(find.text('Ready to record'), findsOneWidget);
      expect(find.text(preview), findsOneWidget);
      expect(find.text('Start recording'), findsOneWidget);
    });

    testWidgets('previews it while the server has not seen the profile', (
      tester,
    ) async {
      await showEmpty(
        tester,
        outcome: RankedSyncOutcome.cooldown,
        eligibility: (eligible: false, pollCount: 0),
      );

      expect(find.text('Not being tracked yet'), findsOneWidget);
      expect(find.text(preview), findsOneWidget);
    });

    for (final (outcome, title) in [
      (RankedSyncOutcome.queued, 'Server busy'),
      (RankedSyncOutcome.busy, 'Busy for a moment'),
      (RankedSyncOutcome.offline, 'Offline'),
      (RankedSyncOutcome.requestError, "Can't sync right now"),
    ]) {
      testWidgets('leaves the preview out when the problem is "$title"', (
        tester,
      ) async {
        await showEmpty(tester, outcome: outcome);

        expect(find.text(title), findsOneWidget);
        expect(find.text(preview), findsNothing);
      });
    }

    testWidgets('lists the steps: profile, trackers, keep open, play', (
      tester,
    ) async {
      await showEmpty(tester, outcome: RankedSyncOutcome.synced);

      final steps = [
        'Profile linked',
        'Equip Kills and Damage trackers',
        'App is polling (keep it open)',
        'Finish a ranked match',
      ];
      double top(String s) => tester.getTopLeft(find.text(s)).dy;
      for (final s in steps) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      for (var i = 1; i < steps.length; i++) {
        expect(top(steps[i - 1]), lessThan(top(steps[i])), reason: steps[i]);
      }
    });

    testWidgets('the trackers step is a suggestion, not a status', (
      tester,
    ) async {
      await showEmpty(tester, outcome: RankedSyncOutcome.synced);

      expect(find.byIcon(Icons.tune), findsOneWidget);
      // Profile linked and polling are done, finishing a match is next; the
      // trackers step claims none of that.
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });

    testWidgets('the preview is decoration: shapes and dashes, no figures', (
      tester,
    ) async {
      await showEmpty(tester, outcome: RankedSyncOutcome.synced);

      expect(
        find.ancestor(
          of: find.text('RP this split'),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('fits a short screen at large text, and scrolls to the '
        'buttons', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await prefsWith({PrefsKeys.statsRefreshMinutes: 0});
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.5),
          ),
          child: app(prefs: prefs, outcome: RankedSyncOutcome.notTracked),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Start recording'));
      expect(tester.takeException(), isNull);
    });
  });
}
