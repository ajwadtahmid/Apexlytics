import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/api_constants.dart';
import '../../models/player_stats.dart';
import '../../providers/player_provider.dart';
import '../../providers/ranked_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatting/season_utils.dart';
import '../../utils/ranked/ranked_period.dart';
import '../../utils/tracking/snapshot_state_mixin.dart';
import '../../utils/storage/storage.dart';
import '../../utils/notifications.dart';
import '../../utils/theme.dart';
import '../../widgets/profile_manager_sheet.dart';
import '../../widgets/widgets.dart';
import '../ranked/ranked_breakdown_body.dart';
import '../ranked/widgets/ranked_info_sheet.dart';
import '../ranked/widgets/ranked_period_selector.dart'
    show RankedSplitDropdown, RankedWeekStrip;

/// My Stats — the app's default tab. Hosts the player's own snapshot info
/// plus the full Ranked Breakdown (rank header, RP graph, and every Ranked
/// tab), merged into one screen so users don't have to jump between two tabs
/// to see their own numbers.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlayerSet = ref.watch(
      playerSettingsProvider.select((s) => s.isPlayerSet),
    );

    if (!isPlayerSet) return const _PlayerSetupView();
    return const _StatsView();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Player setup (shown when no player linked)
// ═══════════════════════════════════════════════════════════════════════════════

class _PlayerSetupView extends StatelessWidget {
  const _PlayerSetupView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: AppTheme.xl),
            Icon(
              Icons.person_search_outlined,
              size: 72,
              color: AppTheme.accent,
            ),
            SizedBox(height: AppTheme.md),
            Text(
              'Get Started',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: AppTheme.sm),
            Text(
              'Enter your in-game name and platform to start tracking your stats.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.5),
            ),
            SizedBox(height: AppTheme.xl),
            PlayerLookupForm(submitLabel: 'Find My Player'),
            SizedBox(height: AppTheme.sm),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Stats view (shown when player is linked)
// ═══════════════════════════════════════════════════════════════════════════════

class _StatsView extends ConsumerStatefulWidget {
  const _StatsView();

  @override
  ConsumerState<_StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends ConsumerState<_StatsView> {
  Timer? _refreshTimer;
  int? _currentTimerMinutes;

  @override
  void initState() {
    super.initState();
    _setupTimer(ref.read(playerSettingsProvider).statsRefreshMinutes);
    ref.listenManual(
      playerSettingsProvider.select((s) => s.statsRefreshMinutes),
      (_, refreshMinutes) => _setupTimer(refreshMinutes),
    );
    // Defer to post-frame so the provider has settled from the build that just ran.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRefreshIfStale();
    });
  }

  /// Belt-and-suspenders: if the provider already delivered stale cached data
  /// (meaning the background refresh in the notifier may not have fired yet),
  /// explicitly trigger a silent refresh here.
  void _autoRefreshIfStale() {
    if (!mounted) return;
    if (ref.read(myPlayerStatsProvider) case AsyncData(:final value)) {
      if (value.staleAt != null) {
        ref.read(myPlayerStatsProvider.notifier).softRefresh();
      }
    }
  }

  void _setupTimer(int minutes) {
    if (minutes == _currentTimerMinutes) return;
    _currentTimerMinutes = minutes;
    _refreshTimer?.cancel();
    if (minutes <= 0) return;
    _refreshTimer = Timer.periodic(Duration(minutes: minutes), (_) {
      if (mounted) _sync();
    });
  }

  /// Combined manual refresh: both My Stats (`/player`) and Ranked's match
  /// history are independent syncs with their own cooldowns, but there's only
  /// one refresh control in the AppBar, so a tap fires both.
  Future<void> _sync() async {
    final uid = ref.read(playerSettingsProvider).uid;
    final futures = <Future<void>>[];

    if (!ref.read(myPlayerStatsProvider).isLoading) {
      ref.invalidate(myPlayerStatsProvider);
      futures.add(
        ref.read(myPlayerStatsProvider.future).then((_) {}).catchError((
          Object e,
          StackTrace st,
        ) {
          // Error surfaces via myPlayerStatsProvider's AsyncError state in the UI.
          log.w('Stats sync failed', error: e, stackTrace: st);
        }),
      );
    }

    ref.invalidate(rankedSyncProvider(uid));
    futures.add(
      ref.read(rankedSyncProvider(uid).future).then((_) {}).catchError((
        Object e,
        StackTrace st,
      ) {
        // Error surfaces through rankedSyncProvider's own AsyncError state.
        log.w('Ranked sync failed', error: e, stackTrace: st);
      }),
    );

    await Future.wait(futures);
  }

  Future<void> _openOnALS(
    BuildContext context,
    String uid,
    String platform,
  ) async {
    final url = '${ApiConstants.alsProfileBaseUrl}/$platform/$uid';
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      context.showMessage('Could not open link');
    }
  }

  void _openChangePlayer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg),
        ),
      ),
      builder: (_) => const ProfileManagerSheet(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(playerSettingsProvider.select((s) => s.name));
    final uid = ref.watch(playerSettingsProvider.select((s) => s.uid));
    final platform = ref.watch(
      playerSettingsProvider.select((s) => s.platform),
    );
    final compactLegendCards = ref.watch(
      playerSettingsProvider.select((s) => s.compactLegendCards),
    );
    final statsAsync = ref.watch(myPlayerStatsProvider);
    final isSyncing =
        statsAsync.isLoading || ref.watch(rankedSyncProvider(uid)).isLoading;

    // Built purely for the AppBar's split dropdown + week strip — the actual
    // Ranked content (including its own loading/error handling) lives in
    // RankedBreakdownBody, which resolves the same split independently.
    final splits = ref.watch(rankedSplitsProvider(uid)).asData?.value;
    final period = ref.watch(rankedPeriodProvider);
    RankedView? shell;
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
        title: InkWell(
          onTap: () => _openChangePlayer(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flexible so a long name (e.g. a Twitch-style handle) shrinks
              // and ellipsizes instead of overflowing the AppBar — a bare
              // Text here has no width limit and renders the overflow stripes.
              Flexible(
                child: Text(name, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
              const SizedBox(width: AppTheme.xs),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: AppTheme.muted,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: 'Open on ALS',
            onPressed: () => _openOnALS(context, uid, platform),
          ),
          // Tracker-equip help lives on the All Trackers page instead
          // (see RankedAllTrackersScreen).
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How ranked tracking works',
            onPressed: () => showRankedInfoSheet(context),
          ),
          isSyncing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Sync',
                  onPressed: _sync,
                ),
        ],
        // Split + week selection get their own row so they don't compete with
        // the actions above for space — riding in the AppBar's bottom slot
        // keeps them reading as one header surface either way.
        bottom: shell != null ? _AppBarBottom(shell: shell) : null,
      ),
      body: statsAsync.when(
        data: (result) {
          final stats = result.data;
          if (stats == null) {
            return const Center(
              child: Text('No data.', style: TextStyle(color: AppTheme.muted)),
            );
          }
          return _StatsBody(
            stats: stats,
            staleAt: result.staleAt,
            platform: platform,
            compactLegendCards: compactLegendCards,
            onRefresh: _sync,
          );
        },
        loading: () => const _StatsSkeleton(),
        error: (e, _) => ErrorView(
          message: friendlyError(e),
          onAction: () => ref.invalidate(myPlayerStatsProvider),
        ),
      ),
    );
  }
}

/// Split picker (its own row) + week strip, stacked in the AppBar's bottom
/// slot. Only the split row is shown when the split has no week metadata.
class _AppBarBottom extends StatelessWidget implements PreferredSizeWidget {
  final RankedView shell;
  const _AppBarBottom({required this.shell});

  @override
  Size get preferredSize =>
      Size.fromHeight(40 + (shell.weeks.isNotEmpty ? 40 : 0));

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: Center(child: RankedSplitDropdown(view: shell)),
        ),
        if (shell.weeks.isNotEmpty) RankedWeekStrip(view: shell),
      ],
    );
  }
}

class _StatsBody extends ConsumerStatefulWidget {
  final PlayerStats stats;
  final DateTime? staleAt;
  final String platform;
  final bool compactLegendCards;
  final Future<void> Function() onRefresh;

  const _StatsBody({
    required this.stats,
    required this.platform,
    required this.compactLegendCards,
    required this.onRefresh,
    this.staleAt,
  });

  @override
  ConsumerState<_StatsBody> createState() => _StatsBodyState();
}

class _StatsBodyState extends ConsumerState<_StatsBody>
    with SnapshotStateMixin {
  List<LegendStat> _mergedLegends = [];
  List<String> _legendStack = [];
  String? _lastLegend;

  // Guards against a slower earlier load (e.g. from a profile switch)
  // overwriting a faster later one. Same idiom as
  // MyPlayerStatsNotifier._buildGeneration. _lastLegend below is unrelated -
  // it debounces the legend-stack push, not this state write.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initSnapshots();
    _loadAndAppend();
  }

  @override
  void didUpdateWidget(_StatsBody old) {
    super.didUpdateWidget(old);
    if (old.stats.uid != widget.stats.uid ||
        old.stats.rankScore != widget.stats.rankScore ||
        old.stats.currentLegend != widget.stats.currentLegend) {
      // On player switch, pre-populate the new player's existing snapshots
      // before the async work completes so the graph doesn't go blank.
      if (old.stats.uid != widget.stats.uid) _initSnapshots();
      _loadAndAppend();
    }
  }

  void _initSnapshots() {
    final prefs = ref.read(sharedPreferencesProvider);
    initSnapshotFields(
      prefs,
      widget.stats.uid,
      widget.stats.rankedSeason,
      widget.stats.rankScore,
    );
  }

  Future<void> _loadAndAppend() async {
    // Claimed synchronously, before the first await, so no other invocation
    // can interleave between the read and the write.
    final generation = ++_loadGeneration;
    final legend = widget.stats.currentLegend;
    final legendChanged = legend != _lastLegend;
    // Update immediately so concurrent calls don't double-push.
    if (legendChanged) _lastLegend = legend;

    final prefs = ref.read(sharedPreferencesProvider);

    // Upsert the current season before parallel work so loadAllSeasonsSync sees it.
    final season = widget.stats.rankedSeason;
    final seasonChanged = season != null
        ? await upsertSeason(season, prefs)
        : false;
    // A season learned here won't otherwise reach rankedSeasonsProvider's
    // frozen snapshot until the next app launch — invalidate it so the ranked
    // split picker picks it up this session too.
    if (seasonChanged && mounted) ref.invalidate(rankedSeasonsProvider);

    final (snaps, legends, stack) = await (
      // Primes the snapshot cache on first call for this UID.
      appendAndLoadSnapshots(
        widget.stats,
        ref.read(rankedHistoryStoreProvider),
      ),
      mergeLegendStats(widget.stats.legendStats, prefs, uid: widget.stats.uid),
      legendChanged && legend.isNotEmpty
          ? pushToLegendStack(legend, prefs)
          : loadLegendStack(prefs),
    ).wait;
    final historyNetRp = await _historyNetRpThisWeek();
    // A newer load superseded us while we were awaiting - its data is the
    // current profile's, ours may not be.
    if (mounted && generation == _loadGeneration) {
      setState(() {
        snapshots = snaps;
        _mergedLegends = legends;
        _legendStack = stack;
        allSeasons = loadAllSeasonsSync(prefs);
        rpDelta = computeWeekDelta(
          snaps,
          widget.stats.rankedSeason,
          widget.stats.rankScore,
          historyNetRp: historyNetRp,
        );
      });
    }
  }

  // The weekly delta is blended with Ranked's own match-history net RP
  // (`weeklyNetRpProvider`) when available — that's the "more accurate"
  // source, since it comes from real recorded matches rather than a diff
  // between two RP snapshots that could straddle a stats refresh gap.
  Future<int?> _historyNetRpThisWeek() async {
    final week = currentWeekRange(widget.stats.rankedSeason);
    if (week == null) return null;
    return ref.read(
      weeklyNetRpProvider((
        uid: widget.stats.uid,
        start: week.start,
        end: week.end,
        currentRp: widget.stats.rankScore,
      )).future,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    return Column(
      children: [
        if (widget.staleAt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.md,
              AppTheme.md,
              AppTheme.md,
              0,
            ),
            child: StaleBanner(staleAt: widget.staleAt!),
          ),
        Expanded(
          child: RankedBreakdownBody(
            uid: stats.uid,
            stats: stats,
            rpDelta: rpDelta,
            snapshots: snapshots,
            allSeasons: allSeasons,
            legendStats: _mergedLegends,
            compactLegendCards: widget.compactLegendCards,
            legendStack: _legendStack,
            onRefresh: widget.onRefresh,
          ),
        ),
      ],
    );
  }
}

// ── Stats skeleton ────────────────────────────────────────────────────────────

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ShimmerWrapper(
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Player info card
          SurfaceCard(
            padding: const EdgeInsets.all(AppTheme.md),
            radius: AppTheme.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    ShimmerBox(
                      width: 10,
                      height: 10,
                      borderRadius: BorderRadius.all(Radius.circular(5)),
                    ),
                    SizedBox(width: AppTheme.sm),
                    Expanded(child: ShimmerBox(height: 24)),
                    SizedBox(width: AppTheme.sm),
                    ShimmerBox(width: 50, height: 15),
                  ],
                ),
                const SizedBox(height: AppTheme.xs),
                const ShimmerBox(width: 200, height: 16),
                const SizedBox(height: 2),
                const ShimmerBox(width: 140, height: 16),
                const SizedBox(height: AppTheme.md),
                ...List.generate(
                  3,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: ShimmerBox(height: 16)),
                        SizedBox(width: 40),
                        ShimmerBox(width: 60, height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.md),

          // Ranked card — header + icon row + progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShimmerBox(width: 60, height: 18),
              const SizedBox(height: AppTheme.sm),
              SurfaceCard(
                padding: const EdgeInsets.all(AppTheme.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ShimmerBox(
                          width: AppTheme.rankIconSize,
                          height: AppTheme.rankIconSize,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerBox(width: 120, height: 24),
                            SizedBox(height: 6),
                            ShimmerBox(width: 80, height: 16),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.md),
                    const ShimmerBox(
                      height: 6,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ShimmerBox(width: 48, height: 14),
                        ShimmerBox(width: 80, height: 15),
                        ShimmerBox(width: 48, height: 14),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.md),

          // Legend section header + cards
          const ShimmerBox(width: 100, height: 18),
          const SizedBox(height: AppTheme.sm),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.sm),
              child: ShimmerBox(
                height: 90,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
