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
      (_) => ref.invalidate(rankedMatchesProvider(widget.uid)),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(rankedMatchesProvider(widget.uid));
    try {
      await ref.read(rankedMatchesProvider(widget.uid).future);
    } catch (_) {
      // Error surfaces through the provider's AsyncError state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(rankedMatchesProvider(widget.uid));
    final period = ref.watch(rankedPeriodProvider);
    final seasons = ref.watch(rankedSeasonsProvider);

    // Resolve the period view when ranked data is present (null while loading,
    // empty/warming-up, or errored) so the AppBar split action can render.
    final matches = async.asData?.value;
    final resolved = matches != null
        ? resolveRankedView(matches, seasons,
            splitId: period.splitId, weekIndex: period.weekIndex)
        : null;
    final view = (resolved != null && !resolved.isEmpty) ? resolved : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ranked Breakdown'),
        actions: [if (view != null) RankedSplitDropdown(view: view)],
        // Weeks ride in the AppBar's bottom slot so split + weeks read as one
        // header surface instead of a separate floating strip.
        bottom: (view != null && view.weeks.isNotEmpty)
            ? RankedWeekStrip(view: view)
            : null,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          ),
          error: (e, _) => _MessageState(
            icon: Icons.lock_outline,
            title: 'Not available',
            message: friendlyError(e),
            onRetry: _refresh,
          ),
          data: (_) {
            if (view == null) {
              return _MessageState(
                icon: Icons.hourglass_empty,
                title: 'Warming up',
                message:
                    'Ranked history will appear here once a few matches have '
                    'been recorded. Check back soon.',
                onRetry: _refresh,
              );
            }

            final filtered = view.filtered;
            final summary = summarize(filtered);

            return DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    labelStyle:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
          },
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final RankedSummary summary;
  final List<RankedMatch> matches;
  final Future<void> Function() onRefresh;

  const _OverviewTab({
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
          RankedSummaryHeader(summary: summary),
          const SizedBox(height: AppTheme.md),
          RankedRpChart(matches: matches),
          const SizedBox(height: AppTheme.md),
          RankedOverviewHighlights(matches: matches),
          const SizedBox(height: AppTheme.md),
          RankedSessionsCard(matches: matches),
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
