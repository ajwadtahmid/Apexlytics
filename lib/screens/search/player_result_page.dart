import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/api_constants.dart';
import '../../models/player_stats.dart';
import '../../providers/api_provider.dart';
import '../../utils/api_cache.dart' show ApiResult;
import '../../providers/player_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatting/search_utils.dart';
import '../../utils/tracking/snapshot_state_mixin.dart';
import '../../utils/notifications.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart';
import 'player_compare_sheet.dart';

class PlayerResultPage extends ConsumerStatefulWidget {
  final String query;
  final String platform;
  final bool searchByUid;

  const PlayerResultPage({
    super.key,
    required this.query,
    required this.platform,
    this.searchByUid = false,
  });

  @override
  ConsumerState<PlayerResultPage> createState() => _PlayerResultPageState();
}

class _PlayerResultPageState extends ConsumerState<PlayerResultPage> {
  bool _refreshing = false;
  ProviderSubscription? _uidSyncSub;

  @override
  void initState() {
    super.initState();
    // When loaded via the UID endpoint, persist the canonical display name back
    // into the stored favourite so the grey tile shows the right name.
    // fireImmediately: true ensures this also runs on the current cached value,
    // not just future provider updates.
    if (widget.searchByUid) {
      _uidSyncSub = ref.listenManual(
        searchPlayerProvider((
          query: widget.query,
          platform: widget.platform,
          searchByUid: widget.searchByUid,
        )),
        (_, next) {
          if (next case AsyncData<ApiResult<PlayerStats>>(:final value)) {
            if (value.data.uid.isEmpty) return;
            ref
                .read(searchStateProvider.notifier)
                .syncDisplayName(value.data.uid, value.data.name);
          }
        },
        fireImmediately: true,
      );
    }
  }

  @override
  void dispose() {
    _uidSyncSub?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final service = ref.read(playerServiceProvider);
    await refreshAndMarkSynced(
      ref,
      service,
      widget.query,
      widget.platform,
      widget.searchByUid,
    );
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _openOnALS(BuildContext context, String uid, String platform) async {
    final url = '${ApiConstants.alsProfileBaseUrl}/$platform/$uid';
    final success = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!success && context.mounted) {
      context.showMessage('Could not open link');
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(
      searchPlayerProvider((
        query: widget.query,
        platform: widget.platform,
        searchByUid: widget.searchByUid,
      )),
    );
    final stats = statsAsync.whenOrNull(data: (result) => result.data);
    final favorites = ref.watch(searchStateProvider).favorites;
    // Check by UID when available (handles both name- and UID-searched favorites).
    final isFav = stats != null && stats.uid.isNotEmpty
        ? favorites.any((f) => f.uid != null && f.uid == stats.uid)
        : favorites.any(
            (f) => f.query == widget.query && f.platform == widget.platform,
          );
    final myStats = ref
        .watch(myPlayerStatsProvider)
        .whenOrNull(data: (result) => result.data);
    final canCompare =
        stats != null &&
        myStats != null &&
        myStats.uid.isNotEmpty &&
        myStats.uid != stats.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(stats?.name ?? widget.query),
        actions: [
          if (canCompare)
            IconButton(
              icon: const Icon(Icons.compare_arrows),
              tooltip: 'Compare Stats',
              onPressed: () => _showComparePicker(context, myStats, stats),
            ),
          if (stats != null) ...[
            IconButton(
              icon: const Icon(Icons.public),
              tooltip: 'Open on ALS',
              onPressed: () => _openOnALS(context, stats.uid, stats.platform),
            ),
            IconButton(
              icon: Icon(
                isFav ? Icons.star : Icons.star_border,
                color: isFav ? AppTheme.accent : AppTheme.muted,
              ),
              onPressed: () {
                ref
                    .read(searchStateProvider.notifier)
                    .toggleFavorite(
                      PlayerRef(
                        query: stats.name,
                        platform: widget.platform,
                        uid: stats.uid.isNotEmpty ? stats.uid : null,
                        searchedByUid: widget.searchByUid,
                      ),
                    );
              },
            ),
          ],
          _refreshing
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
                  onPressed: _refresh,
                ),
        ],
      ),
      body: statsAsync.when(
        data: (result) => PlayerResultBody(
          stats: result.data,
          staleAt: result.staleAt,
          onRefresh: _refresh,
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
        error: (e, _) => ErrorView(
          message: friendlyError(e),
          onAction: () => Navigator.pop(context),
          actionLabel: 'Back',
          icon: Icons.search_off,
        ),
      ),
    );
  }

  void _showComparePicker(
    BuildContext context,
    PlayerStats me,
    PlayerStats them,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.md,
                  AppTheme.md,
                  AppTheme.md,
                  AppTheme.sm,
                ),
                child: Text(
                  'Compare with ${them.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const Divider(color: AppTheme.surface2, height: 1),
              ListTile(
                leading: const Icon(
                  Icons.emoji_events_outlined,
                  color: AppTheme.accent,
                ),
                title: const Text('Ranked'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showDialog(
                    context: context,
                    builder: (_) =>
                        PlayerCompareSheet(me: me, them: them, selection: 'Ranked'),
                  );
                },
              ),
              const Divider(color: AppTheme.surface2, height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetCtx).size.height * 0.4,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: them.legendStats.length,
                  separatorBuilder: (_, i) =>
                      const Divider(color: AppTheme.surface2, height: 1),
                  itemBuilder: (_, i) {
                    final legend = them.legendStats[i];
                    return ListTile(
                      leading: const Icon(
                        Icons.person_outline,
                        color: AppTheme.muted,
                      ),
                      title: Text(legend.name),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        showDialog(
                          context: context,
                          builder: (_) => PlayerCompareSheet(
                            me: me,
                            them: them,
                            selection: legend.name,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PlayerResultBody extends ConsumerStatefulWidget {
  final PlayerStats stats;
  final DateTime? staleAt;
  final Future<void> Function() onRefresh;

  const PlayerResultBody({
    super.key,
    required this.stats,
    required this.onRefresh,
    this.staleAt,
  });

  @override
  ConsumerState<PlayerResultBody> createState() => _PlayerResultBodyState();
}

class _PlayerResultBodyState extends ConsumerState<PlayerResultBody>
    with SnapshotStateMixin {
  @override
  void initState() {
    super.initState();
    // Populate from the in-memory prefs store synchronously so the graph is
    // present on the very first frame — no layout shift.
    final prefs = ref.read(sharedPreferencesProvider);
    initSnapshotFields(prefs, widget.stats.uid,
        widget.stats.rankedSeason, widget.stats.rankScore);
    // Append the current data point (disk write) and update if a new entry was added.
    appendSnapshotState(prefs, widget.stats);
  }

  @override
  void didUpdateWidget(PlayerResultBody old) {
    super.didUpdateWidget(old);
    if (old.stats.uid != widget.stats.uid) {
      final prefs = ref.read(sharedPreferencesProvider);
      initSnapshotFields(prefs, widget.stats.uid,
          widget.stats.rankedSeason, widget.stats.rankScore);
      appendSnapshotState(prefs, widget.stats);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.read(sharedPreferencesProvider);
    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: () async {
        await widget.onRefresh();
        await appendSnapshotState(prefs, widget.stats);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          if (widget.staleAt != null) ...[
            StaleBanner(staleAt: widget.staleAt!),
            const SizedBox(height: AppTheme.sm),
          ],
          PlayerInfoCard(stats: widget.stats, rpDelta: rpDelta),
          const SizedBox(height: AppTheme.md),
          RankedInfoCard(
            myRp: widget.stats.rankScore,
            platform: widget.stats.platform,
          ),
          const SizedBox(height: AppTheme.md),
          GraphCard(
            snapshots: snapshots,
            currentSeason: widget.stats.rankedSeason,
            allSeasons: allSeasons,
            currentRp: widget.stats.rankScore,
          ),
          const SizedBox(height: AppTheme.md),
          PlayerStatsTabs(legendStats: widget.stats.legendStats),
          const SizedBox(height: AppTheme.lg),
        ],
      ),
    );
  }
}
