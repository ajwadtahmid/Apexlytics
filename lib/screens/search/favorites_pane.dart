import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/api_constants.dart';
import '../../models/player_stats.dart';
import '../../providers/api_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/search_provider.dart';
import '../../utils/error_messages.dart' show AppException;
import '../../utils/formatting/format.dart' show formatNumber;
import '../../utils/formatting/rank_utils.dart' show rankAssetPath, rankLabel;
import '../../utils/formatting/search_utils.dart';
import '../../utils/notifications.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart';
import '../../widgets/rank_badge.dart';

class FavoritesPane extends ConsumerWidget {
  final ValueChanged<PlayerRef> onPick;
  const FavoritesPane({super.key, required this.onPick});

  static const _kRefreshConcurrency = 5;

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Clear favorites?'),
        content: const Text(
          'Your saved favorite players will be removed.',
          style: TextStyle(color: AppTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(searchStateProvider.notifier).clearFavorites();
      if (context.mounted) context.showMessage('Favorites cleared');
    }
  }

  Future<void> _refreshAll(WidgetRef ref, List<PlayerRef> favorites) async {
    final service = ref.read(playerServiceProvider);
    // Process in batches to avoid saturating the API with concurrent requests.
    for (var i = 0; i < favorites.length; i += _kRefreshConcurrency) {
      final batch = favorites.skip(i).take(_kRefreshConcurrency);
      await Future.wait(
        batch.map((fav) {
          final byUid = fav.hasUid;
          final query = byUid ? fav.uid! : fav.query;
          return refreshAndMarkSynced(ref, service, query, fav.platform, byUid);
        }),
      );
    }
  }

  Future<void> _addFavorite(
    BuildContext context,
    WidgetRef ref,
    PlayerRef player,
  ) async {
    try {
      await ref.read(searchStateProvider.notifier).toggleFavorite(player);
    } on AppException catch (e) {
      if (context.mounted) context.showMessage(e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchStateProvider);
    final favorites = state.favorites;
    // A favourite is already one tap away above, so it isn't listed twice.
    final recents = [
      for (final r in state.recents)
        if (!favorites.any((f) => isSamePlayer(f, r))) r,
    ];

    if (favorites.isEmpty && recents.isEmpty) {
      return const Center(
        child: Text(
          'Search for a player above to get started',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accent,
      onRefresh: () => _refreshAll(ref, favorites),
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          if (favorites.isNotEmpty) ...[
            _FavoritesHeader(onClear: () => _confirmClear(context, ref)),
            ...favorites.map(
              (r) => _FavoriteTile(playerRef: r, onTap: () => onPick(r)),
            ),
          ],
          if (recents.isNotEmpty) ...[
            _RecentsHeader(
              onClear: () =>
                  ref.read(searchStateProvider.notifier).clearRecents(),
            ),
            ...recents.map(
              (r) => _RecentTile(
                playerRef: r,
                onTap: () => onPick(r),
                onFavorite: () => _addFavorite(context, ref, r),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentsHeader extends StatelessWidget {
  final VoidCallback onClear;
  const _RecentsHeader({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppTheme.sm,
        bottom: AppTheme.sm,
        left: AppTheme.xs,
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 14, color: AppTheme.muted),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Recent',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.sm),
            ),
            child: const Text(
              'Clear',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final PlayerRef playerRef;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  const _RecentTile({
    required this.playerRef,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history, size: 18, color: AppTheme.muted),
      title: Text(playerRef.query),
      subtitle: Text(
        ApiConstants.labelFor(playerRef.platform),
        style: AppTheme.caption,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.star_border, color: AppTheme.accent),
        tooltip: 'Add to favorites',
        onPressed: onFavorite,
      ),
      onTap: onTap,
    );
  }
}

class _FavoritesHeader extends StatelessWidget {
  final VoidCallback onClear;
  const _FavoritesHeader({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.sm, left: AppTheme.xs),
      child: Row(
        children: [
          const Icon(Icons.star, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Favorites',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: AppTheme.xs,
              ),
              decoration: BoxDecoration(
                color: AppTheme.red.withAlpha(25),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: const Text(
                'Clear All',
                style: TextStyle(
                  color: AppTheme.red,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteTile extends ConsumerWidget {
  final PlayerRef playerRef;
  final VoidCallback onTap;

  const _FavoriteTile({required this.playerRef, required this.onTap});

  String _sessionKey() {
    if (playerRef.uid != null && playerRef.uid!.isNotEmpty) {
      return playerRef.uid!;
    }
    return playerSessionKey(playerRef.platform, playerRef.query);
  }

  /// Returns cached stats or null if not available.
  PlayerStats? _getCachedStats(WidgetRef ref) {
    final service = ref.watch(playerServiceProvider);
    final byUid = playerRef.hasUid;
    final query = byUid ? playerRef.uid! : playerRef.query;

    return service
        .getCachedStats(query, playerRef.platform, searchByUid: byUid)
        ?.data;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final synced = ref.watch(sessionRefreshedProvider).contains(_sessionKey());
    final platformLabel = ApiConstants.labelFor(playerRef.platform);

    String title;
    Color leadingColor;
    Widget subtitle;

    if (!synced) {
      final cachedStats = _getCachedStats(ref);
      leadingColor = AppTheme.muted;

      if (cachedStats == null) {
        title = playerRef.query;
        subtitle = Text(platformLabel, style: AppTheme.caption);
      } else {
        title = cachedStats.name;
        final label = rankLabel(cachedStats);
        final rpText = '${formatNumber(cachedStats.rankScore)} RP';
        final rankAsset = rankAssetPath(cachedStats);

        subtitle = _RankSubtitle(
          platformLabel: platformLabel,
          rankText: label,
          rpText: rpText,
          rankAsset: rankAsset,
        );
      }
    } else {
      final byUid = playerRef.hasUid;
      final statsAsync = ref.watch(
        searchPlayerProvider((
          query: byUid ? playerRef.uid! : playerRef.query,
          platform: playerRef.platform,
          searchByUid: byUid,
        )),
      );
      final stats = statsAsync.whenOrNull(data: (result) => result.data);

      if (statsAsync.hasError) {
        leadingColor = AppTheme.red;
        title = playerRef.query;
        subtitle = const Text(
          'Failed to load',
          style: TextStyle(color: AppTheme.red, fontSize: 12),
        );
      } else if (stats == null) {
        leadingColor = AppTheme.muted;
        title = playerRef.query;
        subtitle = Text(platformLabel, style: AppTheme.caption);
      } else {
        leadingColor = playerPresenceColor(stats);
        title = stats.name;
        final label = rankLabel(stats);
        final rpText = '${formatNumber(stats.rankScore)} RP';
        final rankAsset = rankAssetPath(stats);

        subtitle = _RankSubtitle(
          platformLabel: platformLabel,
          rankText: label,
          rpText: rpText,
          rankAsset: rankAsset,
        );
      }
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: StatusDot(color: leadingColor),
      title: Text(title),
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

class _RankSubtitle extends StatelessWidget {
  final String platformLabel;
  final String rankText;
  final String rpText;
  final String? rankAsset;

  const _RankSubtitle({
    required this.platformLabel,
    required this.rankText,
    required this.rpText,
    required this.rankAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(platformLabel, style: AppTheme.caption),
        const SizedBox(width: AppTheme.xs),
        const Text('·', style: AppTheme.caption),
        const SizedBox(width: AppTheme.xs),
        RankBadge(assetPath: rankAsset, size: 12),
        const SizedBox(width: AppTheme.xs),
        Expanded(
          child: Text(
            '$rankText · $rpText',
            style: AppTheme.caption,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
