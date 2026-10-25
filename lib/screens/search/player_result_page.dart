import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/api_constants.dart';
import '../../models/player_stats.dart';
import '../../providers/api_provider.dart';
import '../../utils/api_cache.dart' show ApiResult;
import '../../providers/player_provider.dart';
import '../../providers/ranked_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatting/search_utils.dart';
import '../../utils/tracking/snapshot_state_mixin.dart';
import '../../utils/notifications.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart';
import 'player_compare_screen.dart';
import '../../utils/navigation_utils.dart';

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
  ProviderSubscription? _recentSub;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    // When loaded via the UID endpoint, persist the canonical display name back
    // into the stored favourite so the grey tile shows the right name.
    // fireImmediately: true ensures this also runs on the current cached value,
    // not just future provider updates.
    _recentSub = ref.listenManual(
      searchPlayerProvider((
        query: widget.query,
        platform: widget.platform,
        searchByUid: widget.searchByUid,
      )),
      (_, next) {
        if (next case AsyncData<ApiResult<PlayerStats>>(:final value)) {
          // Only a lookup that found someone, so a typo never lands in the
          // list.
          if (value.data.uid.isEmpty) return;
          // A favorite's card keeps the newest figures seen, on every load.
          unawaited(
            ref
                .read(searchStateProvider.notifier)
                .updateSnapshot(widget.platform, value.data, at: value.staleAt),
          );
          if (_recorded) return;
          _recorded = true;
          ref
              .read(searchStateProvider.notifier)
              .recordRecent(
                PlayerRef(
                  query: value.data.name,
                  platform: widget.platform,
                  uid: value.data.uid,
                ),
              );
        }
      },
      fireImmediately: true,
    );
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
    _recentSub?.close();
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

  Future<void> _openOnALS(
    BuildContext context,
    String uid,
    String platform,
  ) async {
    final url = '${ApiConstants.alsProfileBaseUrl}/$platform/$uid';
    await openExternalLink(context, Uri.parse(url));
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PlayerCompareScreen(me: myStats, them: stats),
                ),
              ),
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
              onPressed: () async {
                try {
                  await ref
                      .read(searchStateProvider.notifier)
                      .toggleFavorite(
                        PlayerRef(
                          query: stats.name,
                          platform: widget.platform,
                          uid: stats.uid.isNotEmpty ? stats.uid : null,
                          searchedByUid: widget.searchByUid,
                          snapshot: PlayerSnapshot.of(
                            stats,
                            at: statsAsync.value?.staleAt,
                          ),
                        ),
                      );
                } on AppException catch (e) {
                  // At the favourites cap: say so rather than do nothing.
                  if (context.mounted) context.showError(e.message);
                }
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
        error: (e, _) => ErrorCard(
          fullScreen: true,
          icon: Icons.search_off,
          iconColor: AppTheme.red,
          iconSize: 48,
          message: friendlyError(e),
          // Nobody by that name there is most often the wrong platform.
          extra: e is AppException && e.status == 404
              ? _TryOtherPlatforms(
                  query: widget.query,
                  platform: widget.platform,
                  searchByUid: widget.searchByUid,
                )
              : null,
          actionLabel: 'Back',
          onAction: () => Navigator.pop(context),
        ),
      ),
    );
  }
}

/// One button for each other platform the same lookup could be tried on. A
/// name can't be looked up on a platform that only takes UIDs, but a UID can.
class _TryOtherPlatforms extends StatelessWidget {
  final String query;
  final String platform;
  final bool searchByUid;

  const _TryOtherPlatforms({
    required this.query,
    required this.platform,
    required this.searchByUid,
  });

  @override
  Widget build(BuildContext context) {
    final others = [
      for (final p in ApiConstants.platforms)
        if (p != platform && (searchByUid || !ApiConstants.isUidOnly(p))) p,
    ];
    if (others.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.md),
      child: Column(
        children: [
          const Text('Try another platform', style: AppTheme.caption),
          const SizedBox(height: AppTheme.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppTheme.sm,
            runSpacing: AppTheme.sm,
            children: [
              for (final p in others)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerResultPage(
                        query: query,
                        platform: p,
                        searchByUid: searchByUid,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: const BorderSide(color: AppTheme.accent),
                  ),
                  child: Text(ApiConstants.labelFor(p)),
                ),
            ],
          ),
        ],
      ),
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
  /// Whether [uid] is a player the user has actually chosen to track — their
  /// own active profile, or a saved favourite. Search is unscoped (any UID a
  /// player can type), and without this check every result view — including
  /// a one-off lookup that's never favourited — permanently appended to that
  /// UID's `stat_snapshots` series, with no retention cap and no lifecycle.
  /// Reads, not just this write, stay unscoped: an un-favourited player's
  /// existing graph still renders from whatever already accrued.
  bool _isKnownUid(String uid) {
    if (uid.isEmpty) return false;
    if (uid == ref.read(playerSettingsProvider).uid) return true;
    return ref.read(searchStateProvider).favorites.any((f) => f.uid == uid);
  }

  // A season learned here (a different provider subtree than the Ranked section of Stats)
  // won't otherwise reach rankedSeasonsProvider's frozen snapshot until the
  // next app launch — invalidate it so the ranked split picker picks it up
  // this session too.
  Future<void> _appendSnapshot(SharedPreferences prefs) async {
    if (!mounted) return;
    if (!_isKnownUid(widget.stats.uid)) return;
    final changed = await appendSnapshotState(
      prefs,
      ref.read(rankedHistoryStoreProvider),
      widget.stats,
      // Search serves the response cache (up to a day old) without a request;
      // that is not a reading, so it is shown but not recorded.
      staleAt: widget.staleAt,
    );
    if (changed && mounted) ref.invalidate(rankedSeasonsProvider);
  }

  @override
  void initState() {
    super.initState();
    // Populate from the in-memory prefs store synchronously so the graph is
    // present on the very first frame — no layout shift.
    final prefs = ref.read(sharedPreferencesProvider);
    initSnapshotFields(prefs, widget.stats.uid);
    // Append the current data point (disk write) and update if a new entry was added.
    _appendSnapshot(prefs);
  }

  @override
  void didUpdateWidget(PlayerResultBody old) {
    super.didUpdateWidget(old);
    final prefs = ref.read(sharedPreferencesProvider);
    final uidChanged = old.stats.uid != widget.stats.uid;
    if (uidChanged) initSnapshotFields(prefs, widget.stats.uid);
    // Cached data that has just been replaced by a live fetch is the first
    // real reading of this visit (it was skipped while stale). A same-RP one
    // is dropped by the dedup in appendSnapshot.
    final becameFresh =
        widget.staleAt == null &&
        (old.staleAt != null || old.stats.rankScore != widget.stats.rankScore);
    if (uidChanged || becameFresh) _appendSnapshot(prefs);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.read(sharedPreferencesProvider);
    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: () async {
        await widget.onRefresh();
        if (!mounted) return;
        await _appendSnapshot(prefs);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          if (widget.staleAt != null) ...[
            StaleBanner(staleAt: widget.staleAt!),
            const SizedBox(height: AppTheme.sm),
          ],
          PlayerInfoCard(stats: widget.stats),
          const SizedBox(height: AppTheme.md),
          RankedInfoCard(
            myRp: widget.stats.rankScore,
            platform: widget.stats.platform,
            season: widget.stats.rankedSeason,
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
