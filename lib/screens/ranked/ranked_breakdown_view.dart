import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ranked_match.dart';
import '../../providers/ranked_provider.dart';
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

/// The ranked-breakdown content, hosted as the gated Ranked bottom-nav tab. It
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

  // Refresh the view every 10 min while the app is open. The server cron is the
  // authoritative collector; this only refreshes what's displayed.
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
            if (splits.isEmpty) {
              return _MessageState(
                icon: Icons.hourglass_empty,
                title: 'Warming up',
                message:
                    'Ranked history will appear here once a few matches have '
                    'been recorded. Check back soon.',
                onRetry: _refresh,
              );
            }
            // Load only the selected split's matches — never the whole history.
            final effId = shell!.effectiveSplitId;
            final matchesAsync = ref.watch(
                rankedSplitMatchesProvider((uid: widget.uid, splitId: effId)));
            return matchesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
              error: (e, _) => _MessageState(
                icon: Icons.lock_outline,
                title: 'Not available',
                message: friendlyError(e),
                onRetry: _refresh,
              ),
              data: (splitMatches) {
                final view = resolveRankedView(
                  splits: splits,
                  splitMatches: splitMatches,
                  selectedSplitId: effId,
                  weekIndex: period.weekIndex,
                );
                return _tabs(view);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _tabs(RankedView view) {
    final filtered = view.filtered;
    final summary = summarize(filtered);

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(fontSize: 14),
            tabs: [
              Tab(height: 42, text: 'Overview'),
              Tab(height: 42, text: 'Legends'),
              Tab(height: 42, text: 'Maps'),
              Tab(height: 42, text: 'History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(
                  uid: widget.uid,
                  summary: summary,
                  matches: filtered,
                  onRefresh: _refresh,
                ),
                RankedLegendBreakdown(
                  matches: filtered,
                  onRefresh: _refresh,
                ),
                RankedMapBreakdown(
                  matches: filtered,
                  onRefresh: _refresh,
                ),
                // History keeps everything (pubs included), not just
                // the ranked matches that drive the other tabs.
                RankedMatchList(
                  matches: view.history,
                  onRefresh: _refresh,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final String uid;
  final RankedSummary summary;
  final List<RankedMatch> matches;
  final Future<void> Function() onRefresh;

  const _OverviewTab({
    required this.uid,
    required this.summary,
    required this.matches,
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
          RankedOverviewHighlights(matches: matches),
          const SizedBox(height: AppTheme.md),
          RankedSessionsCard(matches: matches, onRefresh: onRefresh),
          const SizedBox(height: AppTheme.md),
          RankedTimeOfDayChart(matches: matches),
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

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
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
              style: const TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: AppTheme.md),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry', style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        ),
      ),
    );
  }
}
