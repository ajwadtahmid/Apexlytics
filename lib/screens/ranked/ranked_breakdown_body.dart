import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/prefs_keys.dart';
import '../../constants/legend_constants.dart' show canonicalLegendName;
import '../../constants/map_constants.dart' show canonicalMapKey;
import '../../constants/rank_constants.dart' show kApexPredatorRank;
import '../../models/player_stats.dart';
import '../../models/ranked_match.dart';
import '../../models/season_meta.dart';
import '../../providers/best_metric_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/ranked_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatting/snapshot_types.dart';
import '../../utils/ranked/ranked_period.dart';
import '../../utils/theme.dart';
import '../../widgets/best_metric_picker.dart';
import '../../widgets/error_card.dart';
import '../../widgets/graph_card.dart' show showSnapshotBackupSheet;
import 'ranked_all_trackers_screen.dart';
import 'ranked_available_now_screen.dart';
import 'ranked_legend_map_matrix_screen.dart';
import 'ranked_compare_tab.dart';
import 'ranked_share_screens.dart';
import 'ranked_personal_records_screen.dart';
import 'ranked_pick_rate_screen.dart';
import 'ranked_sessions_list_screen.dart';
import 'ranked_time_breakdown_screen.dart';
import 'widgets/ranked_breakdown_tables.dart';
import 'widgets/ranked_highlight_cards.dart';
import 'widgets/ranked_info_sheet.dart';
import 'widgets/ranked_match_list.dart';
import 'widgets/ranked_rp_chart.dart';
import 'widgets/ranked_stats_card.dart';
import 'widgets/ranked_summary_header.dart';
import '../../widgets/player_info_card.dart';
import '../../widgets/surface_card.dart';
import '../../widgets/setting_row.dart' show SectionLabel;

/// The ranked-breakdown content — tabs, highlights, and every drill-down —
/// embedded as the lower portion of the Stats tab, below the shared
/// AppBar. Everything, including the player-info card and rank header, lives
/// inside the Overview tab's own single scrollable list rather than a
/// separately-scrolling block pinned above the tabs — one scroll surface per
/// tab, no nested scrollables. It reads everything from providers except the
/// player snapshot and merged legend/weapon trackers (passed in, since those
/// come from the Stats side of the merge) and the combined refresh
/// callback.
class RankedBreakdownBody extends ConsumerStatefulWidget {
  final String uid;
  final PlayerStats stats;
  final List<StatSnapshot> snapshots;
  final Map<String, SeasonMeta> allSeasons;
  final List<LegendStat> legendStats;
  final List<String> legendStack;
  final Future<void> Function() onRefresh;

  const RankedBreakdownBody({
    super.key,
    required this.uid,
    required this.stats,
    required this.snapshots,
    required this.allSeasons,
    required this.legendStats,
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

  // Re-checks every 10 min; only invalidates once the sync cooldown is over.
  static const _kViewRefreshInterval = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(_kViewRefreshInterval, (_) {
      // With a refresh interval set, Stats' own timer already runs this
      // sync (see StatsScreen._sync); both firing back to back started two
      // `/games` requests for the same profile.
      if (ref.read(playerSettingsProvider).statsRefreshMinutes > 0) return;
      // Skip while the sync would only replay its stored outcome.
      if (rankedSyncDue(ref.read(sharedPreferencesProvider), widget.uid)) {
        ref.invalidate(rankedSyncProvider(widget.uid));
      }
    });
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

  // Mirrors the combined Stats + Ranked sync (see StatsScreen._sync), so
  // a manual retry or pull-to-refresh here matches the AppBar's button.
  Future<void> _refresh() => widget.onRefresh();

  @override
  Widget build(BuildContext context) {
    final splitsAsync = ref.watch(rankedSplitsProvider(widget.uid));
    final period = ref.watch(rankedPeriodProvider);
    // The tabs render from the local store, so a failed sync still leaves a
    // populated view — it is just behind whatever upstream has.
    final syncOutcome = ref.watch(rankedSyncProvider(widget.uid)).value;
    final isOffline = syncOutcome == RankedSyncOutcome.offline;
    final isRequestError = syncOutcome == RankedSyncOutcome.requestError;

    return Column(
      children: [
        if (_showCoachMark)
          _InfoCoachMark(
            onLearnMore: _openInfoFromCoachMark,
            onDismiss: _dismissCoachMark,
          ),
        if (isOffline)
          const _SyncIssueBanner(
            icon: Icons.cloud_off,
            message: 'Offline — showing saved history.',
          ),
        if (isRequestError)
          const _SyncIssueBanner(
            icon: Icons.error_outline,
            message: 'Could not sync — showing saved history.',
          ),
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
      return ErrorCard(
        fullScreen: true,
        icon: Icons.radio_button_checked,
        title: 'Ready to record',
        message:
            'Only matches played from now on can be recorded — earlier ones '
            'are not recoverable.',
        header: const _FirstRunPreview(),
        extra: steps,
        actionLabel: 'Start recording',
        onAction: _startRecording,
        onRetry: _refresh,
        onLearnMore: onLearnMore,
        secondaryActionLabel: onViewAvailable != null
            ? 'View available stats'
            : null,
        secondaryActionIcon: Icons.bar_chart,
        onSecondaryAction: onViewAvailable,
      );
    }

    // Recording is on but nothing has arrived - ask the server whether it's
    // actually seeing polls for this UID (costs no /games budget) instead of
    // leaving the user guessing. Skipped for offline/requestError too —
    // neither means "nothing has arrived yet".
    if (recording &&
        outcome != RankedSyncOutcome.offline &&
        outcome != RankedSyncOutcome.requestError) {
      final eligibility = ref.watch(gamesEligibilityProvider(widget.uid)).value;
      if (eligibility != null && !eligibility.eligible) {
        return ErrorCard(
          fullScreen: true,
          icon: Icons.wifi_tethering_off,
          title: 'Not being tracked yet',
          message: switch (eligibility.pollCount) {
            null =>
              'The server can\'t confirm this profile is being tracked yet. '
                  'Keep Apexlytics open - tracking starts within a few '
                  'minutes.',
            0 =>
              'The server hasn\'t seen this profile yet. Keep Apexlytics '
                  'open - tracking starts within a few minutes.',
            _ =>
              'Tracking has paused. Keep Apexlytics open while you play so '
                  'matches keep being recorded.',
          },
          header: const _FirstRunPreview(),
          extra: steps,
          onRetry: _refresh,
          onLearnMore: onLearnMore,
          secondaryActionLabel: onViewAvailable != null
              ? 'View available stats'
              : null,
          secondaryActionIcon: Icons.bar_chart,
          onSecondaryAction: onViewAvailable,
        );
      }
    }

    final (title, icon, statusNote) = switch (outcome) {
      RankedSyncOutcome.queued => _queuedState(),
      // Slots are free; the server is only pacing new claims. Say that, not
      // "N slots free, resets in M min", which would contradict itself.
      RankedSyncOutcome.busy => (
        'Busy for a moment',
        Icons.hourglass_top,
        'The history server is pacing new syncs for a minute. Nothing is '
            'lost — tap Retry to try again shortly, or it will retry on its own.',
      ),
      RankedSyncOutcome.offline => (
        'Offline',
        Icons.cloud_off,
        'Couldn\'t reach the server just now — showing the latest we have.',
      ),
      RankedSyncOutcome.requestError => (
        'Can\'t sync right now',
        Icons.error_outline,
        'The server rejected the last request. This usually needs attention '
            'rather than just time — try again later, or re-link your '
            'profile if it keeps happening.',
      ),
      // synced with zero matches so far, cooldown, or still loading
      _ => (
        'Warming up',
        Icons.hourglass_empty,
        'It\'ll appear here once a ranked match ends.',
      ),
    };

    // Waiting on a first match is the first-run case, so it shows the preview;
    // a busy server or a failed request is a different problem and does not.
    final waitingForFirstGame = switch (outcome) {
      RankedSyncOutcome.queued ||
      RankedSyncOutcome.busy ||
      RankedSyncOutcome.offline ||
      RankedSyncOutcome.requestError => false,
      _ => true,
    };

    return ErrorCard(
      fullScreen: true,
      icon: icon,
      title: title,
      message: statusNote,
      header: waitingForFirstGame ? const _FirstRunPreview() : null,
      extra: steps,
      onRetry: _refresh,
      onLearnMore: onLearnMore,
      secondaryActionLabel: onViewAvailable != null
          ? 'View available stats'
          : null,
      secondaryActionIcon: Icons.bar_chart,
      onSecondaryAction: onViewAvailable,
    );
  }

  /// The "queued" empty state's copy. Dynamic when [gamesCapacityProvider]
  /// has an answer — free slot count, or that the budget is locked after a
  /// hiccup (distinct from ordinary congestion) — falling back to generic
  /// copy otherwise.
  (String, IconData, String) _queuedState() {
    final capacity = ref.watch(gamesCapacityProvider).value;
    if (capacity == null) {
      return (
        'Server busy',
        Icons.cloud_queue,
        'The history server is busy right now, but nothing is lost — this '
            'resolves on its own.',
      );
    }
    if (capacity.locked) {
      return (
        'Server busy',
        Icons.cloud_queue,
        'The history server paused briefly after a hiccup upstream — this '
            'clears on its own shortly. Nothing is lost.',
      );
    }
    final resetMinutes = capacity.windowResetsAt
        .difference(DateTime.now())
        .inMinutes
        .clamp(0, 60);
    return (
      'Server busy',
      Icons.cloud_queue,
      '${capacity.free} of ${capacity.maxPerHour} history slots free right '
          'now — resets in about $resetMinutes min. Nothing is lost.',
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
  Widget _errorState(Object e) => ErrorCard(
    fullScreen: true,
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
      child: _OverviewOnReselect(
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
    List<RankedMatch> legendFiltered(String legend) =>
        filtered.where((m) => canonicalLegendName(m.legend) == legend).toList();
    Future<List<RankedMatch>> legendMatches(String legend) async =>
        legendFiltered(legend);
    // Compares canonically, not by exact key: mapBreakdowns already merges
    // map-key variants (e.g. `edistrict`/`edistrict_rotation`) into one row,
    // so its drill-down must return every match behind that row, not just
    // the ones under whichever raw key happened to be its representative.
    List<RankedMatch> mapFiltered(String mapKey) => filtered
        .where((m) => canonicalMapKey(m.mapKey) == canonicalMapKey(mapKey))
        .toList();
    Future<List<RankedMatch>> mapMatches(String mapKey) async =>
        mapFiltered(mapKey);

    return _tabShell(
      'split',
      const ['Overview', 'Legends', 'Maps', 'Games'],
      [
        _OverviewTab(
          uid: widget.uid,
          stats: widget.stats,
          snapshots: widget.snapshots,
          allSeasons: widget.allSeasons,
          data: data,
          legendStats: widget.legendStats,
          legendStack: widget.legendStack,
          legendMatchesFor: legendMatches,
          mapMatchesFor: mapMatches,
          onRefresh: _refresh,
        ),
        RankedLegendBreakdown(
          rows: legends,
          matchesFor: legendMatches,
          onRefresh: _refresh,
          sessionPool: view.history,
        ),
        RankedMapBreakdown(
          rows: maps,
          matchesFor: mapMatches,
          onRefresh: _refresh,
          sessionPool: view.history,
        ),
        // History keeps everything (pubs included), not just the ranked matches.
        RankedMatchList(matches: view.history, onRefresh: _refresh),
      ],
    );
  }

  Widget _lifetimeTabs(RankedLifetimeAggregates agg) {
    final store = ref.read(rankedHistoryStoreProvider);
    // Lifetime spans every split, and RP resets each split — so a lifetime
    // net-RP figure would sum across those resets. The rank header and RP
    // graph are both built on that figure, so they're hidden here.
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
              const SectionLabel(
                label: 'Your account',
                icon: Icons.person_outline,
              ),
              PlayerInfoCard(stats: widget.stats),
              const SizedBox(height: AppTheme.lg),
              const SectionLabel(
                label: 'All time',
                icon: Icons.leaderboard_outlined,
              ),
              RankedStatsCard(summary: agg.summary),
              const SizedBox(height: AppTheme.lg),
              const SectionLabel(
                label: 'Highlights',
                icon: Icons.star_outline,
                trailing: BestMetricPill(),
              ),
              RankedOverviewHighlights(
                metric: ref.watch(bestMetricProvider),
                legends: agg.legends,
                maps: agg.maps,
                legendMatchesFor: (legend) =>
                    store.matchesForLegend(widget.uid, legend),
                mapMatchesFor: (mapKey) =>
                    store.matchesForMap(widget.uid, mapKey),
                onRefresh: _refresh,
              ),
              const SizedBox(height: AppTheme.lg),
              const SectionLabel(
                label: 'Dig deeper',
                icon: Icons.explore_outlined,
              ),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: RankedAllTrackersEntry(
                        legendStats: widget.legendStats,
                        legendStack: widget.legendStack,
                      ),
                    ),
                    const SizedBox(width: AppTheme.sm),
                    Expanded(
                      child: RankedPickRateEntry(
                        summary: agg.summary,
                        legends: agg.legends,
                        matchesFor: (legend) =>
                            store.matchesForLegend(widget.uid, legend),
                        onRefresh: _refresh,
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

class _OverviewTab extends ConsumerWidget {
  final String uid;
  final PlayerStats stats;
  final List<StatSnapshot> snapshots;
  final Map<String, SeasonMeta> allSeasons;

  /// Every split-scoped aggregate, already computed by
  /// [rankedSplitViewProvider] - kept as one record so nothing here gets
  /// recomputed by accident.
  final RankedSplitView data;

  final List<LegendStat> legendStats;
  final List<String> legendStack;
  final Future<List<RankedMatch>> Function(String) legendMatchesFor;
  final Future<List<RankedMatch>> Function(String) mapMatchesFor;
  final Future<void> Function() onRefresh;

  const _OverviewTab({
    required this.uid,
    required this.stats,
    required this.snapshots,
    required this.allSeasons,
    required this.data,
    required this.legendStats,
    required this.legendStack,
    required this.legendMatchesFor,
    required this.mapMatchesFor,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = data.summary;
    final matches = data.view.filtered;
    final legends = data.legends;
    final maps = data.maps;
    // stats.rankScore is always the player's *live* RP, regardless of which
    // split is on screen — comparing it against an old split's final RP
    // reads as "not synced" forever. Only feed it through when the split on
    // screen is the one live RP belongs to (mirrors graph_card.dart's
    // isCurrentSeason check).
    final isCurrentSplit = data.view.effectiveSplitId == stats.rankedSeason?.id;
    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          const SectionLabel(label: 'Your account', icon: Icons.person_outline),
          PlayerInfoCard(stats: stats),
          const SizedBox(height: AppTheme.lg),
          SectionLabel(
            label: data.view.weekIndex >= 0 ? 'This week' : 'This split',
            icon: Icons.leaderboard_outlined,
          ),
          RankedSummaryHeader(
            summary: summary,
            uid: uid,
            splitId: data.view.effectiveSplitId,
            livePlayerRp: isCurrentSplit && data.rpScope.live
                ? stats.rankScore
                : null,
            rpScope: data.rpScope,
          ),
          const SizedBox(height: AppTheme.md),
          RankedRpChart(
            matches: matches,
            sessions: data.sessions,
            weeks: data.view.weeks,
            weekIndex: data.view.weekIndex,
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
          const SizedBox(height: AppTheme.lg),
          const SectionLabel(
            label: 'Highlights',
            icon: Icons.star_outline,
            trailing: BestMetricPill(),
          ),
          RankedOverviewHighlights(
            metric: ref.watch(bestMetricProvider),
            legends: legends,
            maps: maps,
            legendMatchesFor: legendMatchesFor,
            mapMatchesFor: mapMatchesFor,
            onRefresh: onRefresh,
            // The split's full history, for sessions on the drill-down pages.
            sessionPool: data.view.history,
          ),
          const SizedBox(height: AppTheme.lg),
          const SectionLabel(label: 'Dig deeper', icon: Icons.explore_outlined),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: RankedAllTrackersEntry(
                    legendStats: legendStats,
                    legendStack: legendStack,
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(
                  child: RankedLegendMapMatrixEntry(
                    matches: matches,
                    onRefresh: onRefresh,
                    sessionPool: data.view.history,
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
                  child: RankedPickRateEntry(
                    summary: summary,
                    legends: legends,
                    matchesFor: legendMatchesFor,
                    onRefresh: onRefresh,
                    sessionPool: data.view.history,
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(
                  child: RankedTimeBreakdownEntry(
                    hourBuckets: data.timeOfDay,
                    weekdayBuckets: data.dayOfWeek,
                    sessions: data.sessions,
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
                  child: RankedCompareEntry(
                    uid: uid,
                    splits: data.view.splits,
                    matches: matches,
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(
                  child: RankedSessionsEntry(
                    sessions: data.sessions,
                    onRefresh: onRefresh,
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
                  child: RankedRecapEntry(
                    matches: matches,
                    // The week is said under the RP, so not here as well.
                    scope: recapScopeLabel(data.view, week: false),
                    periodPhrase: recapPeriodPhrase(data.view),
                    playerName: stats.name,
                    isPredator:
                        isCurrentSplit &&
                        data.rpScope.live &&
                        stats.rank == kApexPredatorRank,
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(
                  child: RankedPersonalRecordsEntry(
                    stats: stats,
                    matches: matches,
                    sessions: data.sessions,
                    live: data.rpScope.live,
                    onRefresh: onRefresh,
                    scope: recapScopeLabel(data.view),
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

enum _StepStatus {
  done,
  active,
  pending,

  /// Worth doing, but nothing here can tell whether it has been.
  tip,
}

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
          const _StepRow('Equip Kills and Damage trackers', _StepStatus.tip),
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
      _StepStatus.tip => (Icons.tune, AppTheme.muted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppTheme.sm),
          // Wraps rather than runs off a narrow screen or large text.
          Flexible(
            child: Text(
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
          ),
        ],
      ),
    );
  }
}

/// Strip shown above the tabs when the last sync failed and persisted
/// history is still on screen — [RankedSyncOutcome.offline] or `.requestError`,
/// each with its own copy (see `build()`). Sits alongside the tabs rather
/// than replacing them, unlike the [ErrorCard] states above.
class _SyncIssueBanner extends StatelessWidget {
  final IconData icon;
  final String message;

  const _SyncIssueBanner({required this.icon, required this.message});

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
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.orange, fontSize: 12),
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

/// Sends the tab bar below it back to Overview whenever Stats is tapped in
/// the nav bar while it is already showing.
class _OverviewOnReselect extends ConsumerWidget {
  final Widget child;
  const _OverviewOnReselect({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(statsReselectProvider, (_, _) {
      final controller = DefaultTabController.of(context);
      if (controller.index != 0) controller.animateTo(0);
    });
    return child;
  }
}

/// A greyed-out sketch of the page, shown while there is nothing to show yet, so
/// a new player sees what the checklist below is working towards. Purely
/// decorative: made-up shapes, never numbers.
class _FirstRunPreview extends StatelessWidget {
  const _FirstRunPreview();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        children: [
          const Text(
            'WHAT YOU WILL SEE HERE',
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppTheme.sm),
          Opacity(
            opacity: 0.4,
            child: SurfaceCard(
              padding: const EdgeInsets.all(AppTheme.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RP this split',
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppTheme.sm),
                  SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: CustomPaint(painter: _PreviewLinePainter()),
                  ),
                  const SizedBox(height: AppTheme.md),
                  const Row(
                    children: [
                      Expanded(child: _PreviewStat('Games')),
                      Expanded(child: _PreviewStat('RP per game')),
                      Expanded(child: _PreviewStat('Win rate')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  final String label;
  const _PreviewStat(this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '—',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(label, style: AppTheme.caption),
        ),
      ],
    );
  }
}

/// A climbing line with a soft fill: the shape of an RP chart, with no data.
class _PreviewLinePainter extends CustomPainter {
  static const _points = [
    Offset(0, 0.85),
    Offset(0.14, 0.7),
    Offset(0.28, 0.76),
    Offset(0.43, 0.5),
    Offset(0.58, 0.58),
    Offset(0.74, 0.3),
    Offset(0.88, 0.36),
    Offset(1, 0.12),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final line = Path();
    for (final (i, p) in _points.indexed) {
      final x = p.dx * size.width;
      final y = p.dy * size.height;
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = AppTheme.accent.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PreviewLinePainter old) => false;
}
