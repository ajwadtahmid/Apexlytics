import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/prefs_keys.dart';
import '../../models/ranked_match.dart';
import '../../providers/ranked_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/ranked/ranked_period.dart';
import '../../utils/theme.dart';
import 'widgets/ranked_breakdown_tables.dart';
import 'widgets/ranked_highlight_cards.dart';
import 'widgets/ranked_info_sheet.dart';
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
  bool _showCoachMark = false;

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
    final prefs = ref.read(sharedPreferencesProvider);
    _showCoachMark =
        !(prefs.getBool(PrefsKeys.rankedInfoCoachMarkShown) ?? false);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _dismissCoachMark() async {
    setState(() => _showCoachMark = false);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(PrefsKeys.rankedInfoCoachMarkShown, true);
  }

  void _openInfoFromCoachMark() {
    showRankedInfoSheet(context);
    _dismissCoachMark();
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
    // The tabs render from the local store, so a failed sync still leaves a
    // populated view — it is just behind whatever upstream has.
    final isOffline =
        ref.watch(rankedSyncProvider(widget.uid)).value ==
        RankedSyncOutcome.offline;

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
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How tracking works',
            onPressed: () => showRankedInfoSheet(context),
          ),
          if (shell != null) RankedSplitDropdown(view: shell),
        ],
        // Weeks ride in the AppBar's bottom slot so split + weeks read as one
        // header surface instead of a separate floating strip.
        bottom: (shell != null && shell.weeks.isNotEmpty)
            ? RankedWeekStrip(view: shell)
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_showCoachMark)
              _InfoCoachMark(
                onLearnMore: _openInfoFromCoachMark,
                onDismiss: _dismissCoachMark,
              ),
            if (isOffline) const _OfflineBanner(),
            Expanded(
              child: splitsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent),
                ),
                error: (e, _) => _errorState(e),
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
                        rankedSplitViewProvider((
                          uid: widget.uid,
                          splitId: effId,
                        )),
                      )
                      .when(
                        loading: _spinner,
                        error: (e, _) => _errorState(e),
                        data: _splitTabs,
                      );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spinner() =>
      const Center(child: CircularProgressIndicator(color: AppTheme.accent));

  /// What to say when there is no history yet. Title/icon are distinct per
  /// outcome (no data, server busy, offline); [_TrackingSteps] carries the
  /// shared "what's actually happening" progress regardless of which one.
  ///
  /// Uses `.value` rather than `.asData?.value`: during a refresh the provider
  /// briefly has no `AsyncData`, and `.value` keeps the last known outcome
  /// instead of dropping to the least informative branch on every retry.
  Widget _emptyState() {
    final outcome = ref.watch(rankedSyncProvider(widget.uid)).value;
    final recording = ref.watch(
      playerSettingsProvider.select((s) => s.statsRefreshMinutes > 0),
    );

    final steps = _TrackingSteps(recording: recording);
    void onLearnMore() => showRankedInfoSheet(context);

    // Nothing is being recorded for this UID at all — the only state that
    // needs an action rather than just patience.
    if (outcome == RankedSyncOutcome.notTracked && !recording) {
      return _MessageState(
        icon: Icons.radio_button_checked,
        title: 'Ready to record',
        message:
            'Only matches played from now on can be recorded — earlier ones '
            'are not recoverable.',
        steps: steps,
        actionLabel: 'Start recording',
        onAction: _startRecording,
        onRetry: _refresh,
        onLearnMore: onLearnMore,
      );
    }

    final (title, icon, statusNote) = switch (outcome) {
      RankedSyncOutcome.queued => (
        'Server busy',
        Icons.cloud_queue,
        'The history server is busy right now, but nothing is lost — this '
            'resolves on its own.',
      ),
      RankedSyncOutcome.offline => (
        'Offline',
        Icons.cloud_off,
        'Couldn\'t reach the server just now — showing the latest we have.',
      ),
      // synced with zero matches so far, cooldown, or still loading
      _ => (
        'Warming up',
        Icons.hourglass_empty,
        'It\'ll appear here once a ranked match ends.',
      ),
    };

    return _MessageState(
      icon: icon,
      title: title,
      message: statusNote,
      steps: steps,
      onRetry: _refresh,
      onLearnMore: onLearnMore,
    );
  }

  /// The breakdown opt-in: sets 5-minute polling (the floor for reliable match
  /// capture) and Keep screen on (the poll timer only fires in the foreground).
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

  /// Shown when the sync failed and there is no persisted history to fall back
  /// on, which is a cold start without a working connection.
  Widget _errorState(Object e) => _MessageState(
    icon: Icons.cloud_off,
    title: 'Can\'t load history',
    message: friendlyError(e),
    onRetry: _refresh,
    onLearnMore: () => showRankedInfoSheet(context),
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

  /// Optional progress breakdown (e.g. [_TrackingSteps]) shown below the
  /// message.
  final Widget? steps;

  /// Optional link to the full explainer sheet.
  final VoidCallback? onLearnMore;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    this.actionLabel,
    this.onAction,
    this.steps,
    this.onLearnMore,
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
            ?steps,
            const SizedBox(height: AppTheme.md),
            if (actionLabel != null && onAction != null) ...[
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
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
            if (onLearnMore != null)
              TextButton(
                onPressed: onLearnMore,
                child: const Text(
                  'How does this work?',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _StepStatus { done, active, pending }

/// The 3-step path from an empty breakdown to a populated one, shared across
/// every empty-state title/message so "what's actually happening" reads the
/// same regardless of why the wait is happening.
class _TrackingSteps extends StatelessWidget {
  final bool recording;

  const _TrackingSteps({required this.recording});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepRow('Profile linked', _StepStatus.done),
          _StepRow(
            'App is polling (keep it open)',
            recording ? _StepStatus.done : _StepStatus.active,
          ),
          _StepRow(
            'Finish a ranked match',
            recording ? _StepStatus.active : _StepStatus.pending,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final _StepStatus status;

  const _StepRow(this.label, this.status);

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      _StepStatus.done => (Icons.check_circle, AppTheme.green),
      _StepStatus.active => (Icons.radio_button_checked, AppTheme.accent),
      _StepStatus.pending => (Icons.radio_button_unchecked, AppTheme.muted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppTheme.sm),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: status == _StepStatus.pending
                  ? AppTheme.muted
                  : AppTheme.textPrimary,
              fontWeight: status == _StepStatus.active
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// One-time nudge pointing new visitors at the info icon in the AppBar.
/// Dismissed (or tapped) once, then never shown again.
/// Strip shown above the tabs when the last sync failed and persisted history
/// is still on screen. Sits in the layout alongside the tabs rather than
/// replacing them, unlike [_MessageState].
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.md,
        AppTheme.sm,
        AppTheme.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.sm,
        vertical: AppTheme.sm,
      ),
      decoration: BoxDecoration(
        color: AppTheme.orange.withAlpha(25),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 14, color: AppTheme.orange),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Offline — showing saved history.',
              style: TextStyle(color: AppTheme.orange, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCoachMark extends StatelessWidget {
  final VoidCallback onLearnMore;
  final VoidCallback onDismiss;

  const _InfoCoachMark({required this.onLearnMore, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.md,
        AppTheme.sm,
        AppTheme.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.sm,
        vertical: AppTheme.sm,
      ),
      decoration: BoxDecoration(
        color: AppTheme.accent.withAlpha(30),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.accent.withAlpha(90)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppTheme.accent, size: 18),
          const SizedBox(width: AppTheme.sm),
          Expanded(
            child: GestureDetector(
              onTap: onLearnMore,
              child: const Text(
                'New here? Tap to see how ranked tracking works.',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: AppTheme.muted),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
