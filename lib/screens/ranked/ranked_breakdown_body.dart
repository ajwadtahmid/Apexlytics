import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/prefs_keys.dart';
import '../../constants/legend_constants.dart' show canonicalLegendName;
import '../../constants/map_constants.dart' show canonicalMapKey;
import '../../models/player_stats.dart';
import '../../models/ranked_match.dart';
import '../../models/season_meta.dart';
import '../../providers/ranked_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatting/snapshot_types.dart';
import '../../utils/ranked/ranked_period.dart';
import '../../utils/theme.dart';
import '../../widgets/graph_card.dart' show showSnapshotBackupSheet;
import 'ranked_all_trackers_screen.dart';
import 'ranked_available_now_screen.dart';
import 'ranked_legend_map_matrix_screen.dart';
import 'ranked_personal_records_screen.dart';
import 'ranked_pick_rate_screen.dart';
import 'ranked_squad_sessions_screen.dart';
import 'ranked_time_breakdown_screen.dart';
import 'widgets/ranked_breakdown_tables.dart';
import 'widgets/ranked_highlight_cards.dart';
import 'widgets/ranked_info_sheet.dart';
import 'widgets/ranked_match_list.dart';
import 'widgets/ranked_rp_chart.dart';
import 'widgets/ranked_stats_card.dart';
import 'widgets/ranked_summary_header.dart';
import '../../widgets/player_info_card.dart';

/// The ranked-breakdown content — tabs, highlights, and every drill-down —
/// embedded as the lower portion of the My Stats tab, below the shared
/// AppBar. Everything, including the player-info card and rank header, lives
/// inside the Overview tab's own single scrollable list rather than a
/// separately-scrolling block pinned above the tabs — one scroll surface per
/// tab, no nested scrollables. It reads everything from providers except the
/// player snapshot and merged legend/weapon trackers (passed in, since those
/// come from the My Stats side of the merge) and the combined refresh
/// callback.
class RankedBreakdownBody extends ConsumerStatefulWidget {
  final String uid;
  final PlayerStats stats;
  final int? rpDelta;
  final List<StatSnapshot> snapshots;
  final Map<String, SeasonMeta> allSeasons;
  final List<LegendStat> legendStats;
  final bool compactLegendCards;
  final List<String> legendStack;
  final Future<void> Function() onRefresh;

  const RankedBreakdownBody({
    super.key,
    required this.uid,
    required this.stats,
    required this.rpDelta,
    required this.snapshots,
    required this.allSeasons,
    required this.legendStats,
    required this.compactLegendCards,
    required this.legendStack,
    required this.onRefresh,
  });

  @override
  ConsumerState<RankedBreakdownBody> createState() =>
      _RankedBreakdownBodyState();
}

class _RankedBreakdownBodyState extends ConsumerState<RankedBreakdownBody> {
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

  // Mirrors the combined My Stats + Ranked sync (see StatsScreen._sync), so
  // a manual retry or pull-to-refresh here matches the AppBar's button.
  Future<void> _refresh() => widget.onRefresh();

  @override
  Widget build(BuildContext context) {
    final splitsAsync = ref.watch(rankedSplitsProvider(widget.uid));
    final period = ref.watch(rankedPeriodProvider);
    // The tabs render from the local store, so a failed sync still leaves a
    // populated view — it is just behind whatever upstream has.
    final isOffline =
        ref.watch(rankedSyncProvider(widget.uid)).value ==
        RankedSyncOutcome.offline;

    return Column(
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
              final effId = effectiveSplitId(splits, period.splitId);

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
      ],
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
    // The RP graph and All Trackers read from the snapshot store and the live
    // player-stats API respectively, neither gated on the match history this
    // empty state is waiting on — so route to them whenever either has data.
    final onViewAvailable =
        (widget.snapshots.isNotEmpty || widget.legendStats.isNotEmpty)
        ? _openAvailableNow
        : null;

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
        onViewAvailable: onViewAvailable,
      );
    }

    // Recording is on but nothing has arrived - ask the server whether it's
    // actually seeing polls for this UID (costs no /games budget) instead of
    // leaving the user guessing.
    if (recording && outcome != RankedSyncOutcome.offline) {
      final eligibility = ref.watch(gamesEligibilityProvider(widget.uid)).value;
      if (eligibility != null && !eligibility.eligible) {
        return _MessageState(
          icon: Icons.wifi_tethering_off,
          title: 'Not being tracked yet',
          message: eligibility.pollCount == 0
              ? 'The server hasn\'t seen this profile yet. Keep Apexlytics '
                    'open - tracking starts within a few minutes.'
              : 'Tracking has paused. Keep Apexlytics open while you play so '
                    'matches keep being recorded.',
          steps: steps,
          onRetry: _refresh,
          onLearnMore: onLearnMore,
          onViewAvailable: onViewAvailable,
        );
      }
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
      onViewAvailable: onViewAvailable,
    );
  }

  /// Opens the RP graph and All Trackers, built from the snapshot store and
  /// player-stats API this widget already holds, independent of match history.
  void _openAvailableNow() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankedAvailableNowScreen(
          snapshots: widget.snapshots,
          currentSeason: widget.stats.rankedSeason,
          allSeasons: widget.allSeasons,
          currentRp: widget.stats.rankScore,
          legendStats: widget.legendStats,
          compact: widget.compactLegendCards,
          legendStack: widget.legendStack,
        ),
      ),
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
    final legends = data.legends;
    final maps = data.maps;

    // For a split the matches are already in memory — the drill-down just
    // filters them (wrapped in a Future to share the widgets' lazy signature).
    // Defined once here and passed down; _OverviewTab used to declare a
    // byte-identical pair of its own.
    //
    // Compares canonically, not by exact string: legendBreakdowns already
    // merges legend-name case variants (e.g. a match with a raw
    // "bloodhound") into one canonically-named row, so its drill-down must
    // return every match behind that row, not just the ones under whichever
    // raw casing happened to be more common. Same reasoning as mapMatches
    // below, for map-key variants.
    Future<List<RankedMatch>> legendMatches(String legend) async => filtered
        .where((m) => canonicalLegendName(m.legend) == legend)
        .toList();
    // Compares canonically, not by exact key: mapBreakdowns already merges
    // map-key variants (e.g. `edistrict`/`edistrict_rotation`) into one row,
    // so its drill-down must return every match behind that row, not just
    // the ones under whichever raw key happened to be its representative.
    Future<List<RankedMatch>> mapMatches(String mapKey) async => filtered
        .where((m) => canonicalMapKey(m.mapKey) == canonicalMapKey(mapKey))
        .toList();

    return _tabShell(
      'split',
      const ['Overview', 'Legends', 'Maps', 'History'],
      [
        _OverviewTab(
          uid: widget.uid,
          stats: widget.stats,
          rpDelta: widget.rpDelta,
          snapshots: widget.snapshots,
          allSeasons: widget.allSeasons,
          data: data,
          legendStats: widget.legendStats,
          compactLegendCards: widget.compactLegendCards,
          legendStack: widget.legendStack,
          legendMatchesFor: legendMatches,
          mapMatchesFor: mapMatches,
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
    // Lifetime spans every split, and RP resets each split — so a lifetime
    // net-RP figure would sum across those resets (the exact bug documented
    // in WEEKLY_RP_FIX_REPORT.md). The rank header and RP graph are both
    // built on that figure, so they're hidden here, same as the graph.
    return _tabShell(
      'lifetime',
      const ['Overview', 'Legends', 'Maps'],
      [
        // Lifetime overview: aggregate stats, highlights, and time-of-day.
        // Sessions are omitted too — too heavy at lifetime scale. Time-of-day
        // only needs start time + RP, so it's a good Lifetime fit and is fed
        // by a lightweight SQL projection, not full match hydration.
        RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.md),
            children: [
              PlayerInfoCard(stats: widget.stats, rpDelta: widget.rpDelta),
              const SizedBox(height: AppTheme.md),
              RankedStatsCard(summary: agg.summary),
              const SizedBox(height: AppTheme.md),
              RankedOverviewHighlights(
                legends: agg.legends,
                maps: agg.maps,
                legendMatchesFor: (legend) =>
                    store.matchesForLegend(widget.uid, legend),
                mapMatchesFor: (mapKey) =>
                    store.matchesForMap(widget.uid, mapKey),
                onRefresh: _refresh,
              ),
              const SizedBox(height: AppTheme.md),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: RankedAllTrackersEntry(
                        legendStats: widget.legendStats,
                        compact: widget.compactLegendCards,
                        legendStack: widget.legendStack,
                      ),
                    ),
                    const SizedBox(width: AppTheme.sm),
                    Expanded(
                      child: RankedPickRateEntry(
                        summary: agg.summary,
                        legends: agg.legends,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.md),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: RankedPersonalBestEntry(uid: widget.uid)),
                    const SizedBox(width: AppTheme.sm),
                    Expanded(
                      child: RankedTimeBreakdownEntry(
                        hourBuckets: agg.timeOfDay,
                        weekdayBuckets: agg.dayOfWeek,
                      ),
                    ),
                  ],
                ),
              ),
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
  final PlayerStats stats;
  final int? rpDelta;
  final List<StatSnapshot> snapshots;
  final Map<String, SeasonMeta> allSeasons;

  /// Every split-scoped aggregate, already computed by
  /// [rankedSplitViewProvider] - kept as one record so nothing here gets
  /// recomputed by accident.
  final RankedSplitView data;

  final List<LegendStat> legendStats;
  final bool compactLegendCards;
  final List<String> legendStack;
  final Future<List<RankedMatch>> Function(String) legendMatchesFor;
  final Future<List<RankedMatch>> Function(String) mapMatchesFor;
  final Future<void> Function() onRefresh;

  const _OverviewTab({
    required this.uid,
    required this.stats,
    required this.rpDelta,
    required this.snapshots,
    required this.allSeasons,
    required this.data,
    required this.legendStats,
    required this.compactLegendCards,
    required this.legendStack,
    required this.legendMatchesFor,
    required this.mapMatchesFor,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final summary = data.summary;
    final matches = data.view.filtered;
    final legends = data.legends;
    final maps = data.maps;
    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          PlayerInfoCard(stats: stats, rpDelta: rpDelta),
          const SizedBox(height: AppTheme.md),
          RankedSummaryHeader(
            summary: summary,
            uid: uid,
            livePlayerRp: stats.rankScore,
          ),
          const SizedBox(height: AppTheme.md),
          RankedRpChart(
            matches: matches,
            sessions: data.sessions,
            onShowBackup: () => showSnapshotBackupSheet(
              context,
              snapshots: snapshots,
              currentSeason: stats.rankedSeason,
              allSeasons: allSeasons,
              currentRp: stats.rankScore,
            ),
          ),
          const SizedBox(height: AppTheme.md),
          RankedStatsCard(summary: summary),
          const SizedBox(height: AppTheme.md),
          RankedOverviewHighlights(
            legends: legends,
            maps: maps,
            legendMatchesFor: legendMatchesFor,
            mapMatchesFor: mapMatchesFor,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: AppTheme.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: RankedAllTrackersEntry(
                    legendStats: legendStats,
                    compact: compactLegendCards,
                    legendStack: legendStack,
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(child: RankedLegendMapMatrixEntry(matches: matches)),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: RankedPickRateEntry(
                    summary: summary,
                    legends: legends,
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(
                  child: RankedTimeBreakdownEntry(
                    hourBuckets: data.timeOfDay,
                    weekdayBuckets: data.dayOfWeek,
                    matches: matches,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: RankedPersonalRecordsEntry(
                    uid: uid,
                    matches: matches,
                    splits: data.view.splits,
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(
                  child: RankedSquadSessionsEntry(
                    fullSquad: data.fullSquad,
                    partialSquad: data.partialSquad,
                    sessions: data.sessions,
                    onRefresh: onRefresh,
                  ),
                ),
              ],
            ),
          ),
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

  /// Optional link to [RankedAvailableNowScreen], shown only when the graph
  /// or trackers it displays actually have data to show.
  final VoidCallback? onViewAvailable;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    this.actionLabel,
    this.onAction,
    this.steps,
    this.onLearnMore,
    this.onViewAvailable,
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
            if (onViewAvailable != null) ...[
              OutlinedButton.icon(
                onPressed: onViewAvailable,
                icon: const Icon(Icons.bar_chart, size: 16),
                label: const Text('View available stats'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: const BorderSide(color: AppTheme.accent),
                ),
              ),
              const SizedBox(height: AppTheme.xs),
            ],
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

/// One-time nudge pointing new visitors at the "How tracking works" AppBar
/// icon. Dismissed (or tapped) once, then never shown again.
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
