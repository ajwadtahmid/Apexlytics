import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/api_constants.dart';
import '../../models/player_stats.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatting/season_utils.dart';
import '../../utils/tracking/snapshot_state_mixin.dart';
import '../../utils/storage/storage.dart';
import '../../utils/notifications.dart';
import '../../utils/theme.dart';
import '../../widgets/profile_manager_sheet.dart';
import '../../widgets/widgets.dart';

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

  Future<void> _sync() async {
    if (ref.read(myPlayerStatsProvider).isLoading) return;
    ref.invalidate(myPlayerStatsProvider);
    try {
      await ref.read(myPlayerStatsProvider.future);
    } catch (e, st) {
      // Error surfaces via myPlayerStatsProvider's AsyncError state in the UI.
      log.w('Stats sync failed', error: e, stackTrace: st);
    }
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

  void _showTrackerInfo(BuildContext context) => showTrackerInfoSheet(context);

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

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => _openChangePlayer(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name),
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
            icon: const Icon(Icons.info_outline),
            tooltip: 'Tracker info',
            onPressed: () => _showTrackerInfo(context),
          ),
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: 'Open on ALS',
            onPressed: () => _openOnALS(context, uid, platform),
          ),
          statsAsync.isLoading
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

class _StatsBody extends ConsumerStatefulWidget {
  final PlayerStats stats;
  final DateTime? staleAt;
  final String platform;
  final bool compactLegendCards;

  const _StatsBody({
    required this.stats,
    required this.platform,
    required this.compactLegendCards,
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
    final legend = widget.stats.currentLegend;
    final legendChanged = legend != _lastLegend;
    // Update immediately so concurrent calls don't double-push.
    if (legendChanged) _lastLegend = legend;

    final prefs = ref.read(sharedPreferencesProvider);

    // Upsert the current season before parallel work so loadAllSeasonsSync sees it.
    final season = widget.stats.rankedSeason;
    if (season != null) await upsertSeason(season, prefs);

    final (snaps, legends, stack) = await (
      appendAndLoadSnapshots(widget.stats, prefs),
      mergeLegendStats(widget.stats.legendStats, prefs, uid: widget.stats.uid),
      legendChanged && legend.isNotEmpty
          ? pushToLegendStack(legend, prefs)
          : loadLegendStack(prefs),
    ).wait;
    if (mounted) {
      setState(() {
        snapshots = snaps;
        _mergedLegends = legends;
        _legendStack = stack;
        allSeasons = loadAllSeasonsSync(prefs);
        rpDelta = computeWeekDelta(
          snaps,
          widget.stats.rankedSeason,
          widget.stats.rankScore,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: () async {
        ref.invalidate(myPlayerStatsProvider);
        try {
          await ref.read(myPlayerStatsProvider.future);
        } catch (e, st) {
          // Error surfaces via myPlayerStatsProvider's AsyncError state in the UI.
          log.w('Stats pull-to-refresh failed', error: e, stackTrace: st);
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          if (widget.staleAt != null) ...[
            StaleBanner(staleAt: widget.staleAt!),
            const SizedBox(height: AppTheme.sm),
          ],
          PlayerInfoCard(stats: stats, rpDelta: rpDelta),
          const SizedBox(height: AppTheme.md),
          RankedInfoCard(myRp: stats.rankScore, platform: widget.platform),
          const SizedBox(height: AppTheme.md),
          GraphCard(
            snapshots: snapshots,
            currentSeason: widget.stats.rankedSeason,
            allSeasons: allSeasons,
            currentRp: widget.stats.rankScore,
          ),
          const SizedBox(height: AppTheme.md),
          PlayerStatsTabs(
            legendStats: _mergedLegends,
            compact: widget.compactLegendCards,
            legendStack: _legendStack,
          ),
          const SizedBox(height: AppTheme.xl),
        ],
      ),
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
