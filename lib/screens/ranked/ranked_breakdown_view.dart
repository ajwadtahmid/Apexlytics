import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ranked_match.dart';
import '../../providers/ranked_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/ranked/ranked_period.dart';
import '../../utils/theme.dart';
import 'widgets/ranked_breakdown_tables.dart';
import 'widgets/ranked_highlight_cards.dart';
import 'widgets/ranked_match_list.dart';
import 'widgets/ranked_period_selector.dart'
    show RankedSplitDropdown, RankedWeekStrip;
import 'widgets/ranked_rp_chart.dart';
import 'widgets/ranked_sessions_card.dart';
import 'widgets/ranked_stats_card.dart';
import 'widgets/ranked_summary_header.dart';
import 'widgets/ranked_time_of_day_chart.dart';

/// The ranked-breakdown content, hosted as the Ranked bottom-nav tab. It
/// owns no Scaffold/AppBar and reads everything from providers, so it can be
/// embedded anywhere (e.g. a future Search-result reuse) without change.
class RankedBreakdownView extends ConsumerStatefulWidget {
  final String uid;

  const RankedBreakdownView({super.key, required this.uid});

  @override
  ConsumerState<RankedBreakdownView> createState() =>
      _RankedBreakdownViewState();
}

class _RankedBreakdownViewState extends ConsumerState<RankedBreakdownView> {
  Timer? _refreshTimer;

  // Re-check every 10 min while the tab is alive. This is cheap: the sync
  // provider holds a persisted per-UID cooldown, so most ticks skip the network
  // entirely and only re-read the local store.
  static const _kViewRefreshInterval = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      _kViewRefreshInterval,
      (_) => ref.invalidate(rankedSyncProvider(widget.uid)),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    // Re-syncing cascades to the split picker and the loaded split's matches,
    // which both await this provider's future.
    ref.invalidate(rankedSyncProvider(widget.uid));
    try {
      await ref.read(rankedSyncProvider(widget.uid).future);
    } catch (_) {
      // Error surfaces through the provider's AsyncError state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final splitsAsync = ref.watch(rankedSplitsProvider(widget.uid));
    final period = ref.watch(rankedPeriodProvider);

    // A matches-free "shell" view (splits + weeks only) so the AppBar's split
    // dropdown and week strip render the moment the picker resolves, before the
    // selected split's matches load. Null until there's at least one split.
    RankedView? shell;
    final splits = splitsAsync.asData?.value;
    if (splits != null && splits.isNotEmpty) {
      final effId = effectiveSplitId(splits, period.splitId);
      final bucket = splits.firstWhere((b) => b.id == effId);
      final weeks = weeksForBucket(bucket);
      final effWeek = (period.weekIndex >= 0 && period.weekIndex < weeks.length)
          ? period.weekIndex
          : -1;
      shell = RankedView(
        splits: splits,
        effectiveSplitId: effId,
        weeks: weeks,
        weekIndex: effWeek,
        filtered: const [],
        history: const [],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranked Breakdown'),
        actions: [if (shell != null) RankedSplitDropdown(view: shell)],
        // Weeks ride in the AppBar's bottom slot so split + weeks read as one
        // header surface instead of a separate floating strip.
        bottom: (shell != null && shell.weeks.isNotEmpty)
            ? RankedWeekStrip(view: shell)
            : null,
      ),
      body: SafeArea(
        child: splitsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          ),
          error: (e, _) => _MessageState(
            icon: Icons.lock_outline,
            title: 'Not available',
            message: friendlyError(e),
            onRetry: _refresh,
          ),
          data: (splits) {
            if (splits.isEmpty) return _emptyState();
            final effId = shell!.effectiveSplitId;

            // Lifetime: every split aggregated in SQL — no matches hydrated.
            if (isLifetimeSplit(effId)) {
              return ref
                  .watch(rankedLifetimeAggregatesProvider(widget.uid))
                  .when(
                    loading: _spinner,
                    error: (e, _) => _errorState(e),
                    data: _lifetimeTabs,
                  );
            }

            // Otherwise load only the selected split's matches (and its
            // aggregates, memoized in the provider rather than recomputed here).
            return ref
                .watch(
                  rankedSplitViewProvider((uid: widget.uid, splitId: effId)),
                )
                .when(
                  loading: _spinner,
                  error: (e, _) => _errorState(e),
                  data: _splitTabs,
                );
          },
        ),
      ),
    );
  }

  Widget _spinner() =>
      const Center(child: CircularProgressIndicator(color: AppTheme.accent));

  /// What to say when there is no history yet.
  ///
  /// The title carries the distinction: "Ready to record" means the user has
  /// to act — nothing is being tracked at all. "Warming up" means tracking is
  /// live and it's a matter of time. But every branch's *message* gives the
  /// same instruction regardless of title, because "Warming up" alone still
  /// reads as passive — the user has to keep the app (or an
  /// apexlegendsstatus.com tab) open and finish a ranked match either way.
  ///
  /// `.value` rather than `.asData?.value` deliberately: during a refresh the
  /// provider briefly has no `AsyncData`, and `asData` would drop straight to
  /// the least informative branch on every retry — `.value` keeps the last
  /// known outcome instead.
  Widget _emptyState() {
    final outcome = ref.watch(rankedSyncProvider(widget.uid)).value;
    final recording = ref.watch(
      playerSettingsProvider.select((s) => s.statsRefreshMinutes > 0),
    );

    // Nothing is being recorded for this UID at all — the only state that
    // needs an action rather than just patience.
    if (outcome == RankedSyncOutcome.notTracked && !recording) {
      return _MessageState(
        icon: Icons.radio_button_checked,
        title: 'Ready to record',
        message:
            'Match history is only recorded while your profile is being '
            'polled — so keep Apexlytics open (or a browser tab on '
            'apexlegendsstatus.com) and finish a ranked match.\n\n'
            'Only matches played from now on can be recorded — earlier ones '
            'are not recoverable.',
        actionLabel: 'Start recording',
        onAction: _startRecording,
        onRetry: _refresh,
      );
    }

    final polls = ref.watch(gamesEligibilityProvider(widget.uid)).value;
    final pollProgress = recording && polls != null && polls.pollCount < 3
        ? ' Polls recorded so far: ${polls.pollCount} of 3 — tracking starts '
            'once that\'s reached.'
        : '';
    final statusNote = switch (outcome) {
      RankedSyncOutcome.queued =>
        ' The history server is busy right now, but nothing is lost — this '
            'resolves on its own.',
      RankedSyncOutcome.offline =>
        ' Couldn\'t reach the server just now — showing the latest we have.',
      _ => '', // synced with zero matches so far, cooldown, or still loading
    };

    return _MessageState(
      icon: Icons.hourglass_empty,
      title: 'Warming up',
      message:
          'Keep Apexlytics open (or a browser tab on apexlegendsstatus.com) '
          'while you play, and finish a ranked match — it\'ll appear here '
          'once it ends.$pollProgress$statusNote',
      onRetry: _refresh,
    );
  }

  /// The breakdown opt-in. Both settings are load-bearing rather than nice to
  /// have: 5 minutes is the measured floor for reliable match capture (a short
  /// game can start and end inside a 10-minute gap), and the poll timer only
  /// fires in the foreground, so a sleeping screen stops recording.
  Future<void> _startRecording() async {
    final settings = ref.read(playerSettingsProvider.notifier);
    await settings.setStatsRefreshMinutes(kRecordingRefreshMinutes);
    await settings.setKeepScreenOn(true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Recording started — keep Apexlytics open while you play.',
        ),
      ),
    );
    await _refresh();
  }

  Widget _errorState(Object e) => _MessageState(
    icon: Icons.lock_outline,
    title: 'Not available',
    message: friendlyError(e),
    onRetry: _refresh,
  );

  /// Tab shell keyed by [key] so switching between a split (4 tabs) and Lifetime
  /// (3 tabs) rebuilds the controller cleanly instead of asserting on a length
  /// change.
  Widget _tabShell(String key, List<String> labels, List<Widget> views) {
    return DefaultTabController(
      key: ValueKey(key),
      length: labels.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
            tabs: [for (final l in labels) Tab(height: 42, text: l)],
          ),
          Expanded(child: TabBarView(children: views)),
        ],
      ),
    );
  }

  Widget _splitTabs(RankedSplitView data) {
    final view = data.view;
    final filtered = view.filtered;
    final summary = data.summary;
    final legends = data.legends;
    final maps = data.maps;

    // For a split the matches are already in memory — the drill-down just
    // filters them (wrapped in a Future to share the widgets' lazy signature).
    Future<List<RankedMatch>> legendMatches(String legend) async =>
        filtered.where((m) => m.legend == legend).toList();
    Future<List<RankedMatch>> mapMatches(String mapKey) async =>
        filtered.where((m) => m.mapKey == mapKey).toList();

    return _tabShell(
      'split',
      const ['Overview', 'Legends', 'Maps', 'History'],
      [
        _OverviewTab(
          uid: widget.uid,
          summary: summary,
          matches: filtered,
          legends: legends,
          maps: maps,
          onRefresh: _refresh,
        ),
        RankedLegendBreakdown(
          rows: legends,
          matchesFor: legendMatches,
          onRefresh: _refresh,
        ),
        RankedMapBreakdown(
          rows: maps,
          matchesFor: mapMatches,
          onRefresh: _refresh,
        ),
        // History keeps everything (pubs included), not just the ranked matches.
        RankedMatchList(matches: view.history, onRefresh: _refresh),
      ],
    );
  }

  Widget _lifetimeTabs(RankedLifetimeAggregates agg) {
    final store = ref.read(rankedHistoryStoreProvider);
    return _tabShell(
      'lifetime',
      const ['Overview', 'Legends', 'Maps'],
      [
        // Lifetime overview: aggregate stats, highlights, and time-of-day. The
        // RP chart, rank-progress header, and sessions are omitted — they're
        // season-relative (RP resets each split) or too heavy at lifetime scale
        // (sessions). Time-of-day only needs start time + RP, so it's a good
        // Lifetime fit and is fed by a lightweight SQL projection, not full
        // match hydration.
        RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.md),
            children: [
              RankedStatsCard(summary: agg.summary),
              const SizedBox(height: AppTheme.md),
              RankedOverviewHighlights(legends: agg.legends, maps: agg.maps),
              const SizedBox(height: AppTheme.md),
              RankedTimeOfDayChart(buckets: agg.timeOfDay),
              const SizedBox(height: AppTheme.lg),
            ],
          ),
        ),
        RankedLegendBreakdown(
          rows: agg.legends,
          matchesFor: (legend) => store.matchesForLegend(widget.uid, legend),
          onRefresh: _refresh,
        ),
        RankedMapBreakdown(
          rows: agg.maps,
          matchesFor: (mapKey) => store.matchesForMap(widget.uid, mapKey),
          onRefresh: _refresh,
        ),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final String uid;
  final RankedSummary summary;
  final List<RankedMatch> matches;
  final List<LegendBreakdown> legends;
  final List<MapBreakdown> maps;
  final Future<void> Function() onRefresh;

  const _OverviewTab({
    required this.uid,
    required this.summary,
    required this.matches,
    required this.legends,
    required this.maps,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          RankedSummaryHeader(summary: summary, uid: uid),
          const SizedBox(height: AppTheme.md),
          RankedStatsCard(summary: summary),
          const SizedBox(height: AppTheme.md),
          RankedRpChart(matches: matches),
          const SizedBox(height: AppTheme.md),
          RankedOverviewHighlights(legends: legends, maps: maps),
          const SizedBox(height: AppTheme.md),
          RankedSessionsCard(matches: matches, onRefresh: onRefresh),
          const SizedBox(height: AppTheme.md),
          RankedTimeOfDayChart(buckets: timeOfDayBuckets(matches)),
          const SizedBox(height: AppTheme.lg),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRetry;

  /// Optional primary action shown above Retry, for states the user can
  /// actually resolve rather than just wait out.
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.muted, size: 40),
            const SizedBox(height: AppTheme.md),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppTheme.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.md),
            if (actionLabel != null && onAction != null) ...[
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                ),
                child: Text(actionLabel!),
              ),
              const SizedBox(height: AppTheme.xs),
            ],
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(color: AppTheme.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
