import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/api_constants.dart';
import '../../models/player_stats.dart';
import '../../providers/api_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/search_provider.dart';
import '../../utils/api_cache.dart' show ApiResult;
import '../../utils/error_messages.dart' show AppException;
import '../../utils/formatting/format.dart' show formatNumber, timeAgo;
import '../../utils/formatting/platform_utils.dart' show platformIconFor;
import '../../utils/formatting/rank_utils.dart'
    show rankAssetPathFor, rankLabelFor;
import '../../utils/formatting/search_utils.dart';
import '../../utils/navigation_utils.dart' show openExternalLink;
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

  /// Saves [player], with whatever its card was showing, so the favorite's
  /// card has something to show from the start.
  Future<void> _addFavorite(
    BuildContext context,
    WidgetRef ref,
    PlayerRef player,
    PlayerSnapshot? shown,
  ) async {
    try {
      await ref
          .read(searchStateProvider.notifier)
          .toggleFavorite(player.withSnapshot(shown));
    } on AppException catch (e) {
      if (context.mounted) context.showMessage(e.message);
    }
  }

  /// Takes [player] off the favorites, with an Undo that puts it back where it
  /// was.
  void _remove(BuildContext context, WidgetRef ref, PlayerRef player) {
    final notifier = ref.read(searchStateProvider.notifier);
    final index = ref.read(searchStateProvider).favorites.indexOf(player);
    unawaited(notifier.removeFavorite(player));
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${player.query} from favorites'),
          // A snackbar with an action otherwise stays until dismissed.
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppTheme.accent,
            onPressed: () async {
              try {
                await notifier.restoreFavorite(player, index);
              } on AppException catch (e) {
                messenger.showError(e.message);
              }
            },
          ),
        ),
      );
  }

  /// What a long press on a favorite offers: the same removal as a swipe, for
  /// anyone who can't swipe, and the player's page on the website.
  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    PlayerRef player,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.star_border, color: AppTheme.red),
              title: const Text('Remove from favorites'),
              onTap: () {
                Navigator.pop(sheetContext);
                _remove(context, ref, player);
              },
            ),
            if (player.hasUid)
              ListTile(
                leading: const Icon(Icons.public, color: AppTheme.accent),
                title: const Text('Open on ALS'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  openExternalLink(
                    context,
                    Uri.parse(
                      '${ApiConstants.alsProfileBaseUrl}/${player.platform}/${player.uid}',
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
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
            _ListHeader(
              icon: Icons.star,
              label: 'Favorites',
              onClear: () => _confirmClear(context, ref),
            ),
            ...favorites.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.sm),
                child: Dismissible(
                  key: ValueKey(
                    'favorite:${r.uid ?? '${r.platform}:${r.query}'}',
                  ),
                  direction: DismissDirection.endToStart,
                  background: const _RemoveBackground(),
                  onDismissed: (_) => _remove(context, ref, r),
                  child: _PlayerCard(
                    playerRef: r,
                    onTap: () => onPick(r),
                    onLongPress: () => _showMenu(context, ref, r),
                  ),
                ),
              ),
            ),
            if (recents.isNotEmpty) const SizedBox(height: AppTheme.sm),
          ],
          if (recents.isNotEmpty) ...[
            _ListHeader(
              icon: Icons.history,
              label: 'Recent',
              onClear: () =>
                  ref.read(searchStateProvider.notifier).clearRecents(),
            ),
            ...recents.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.sm),
                child: _PlayerCard(
                  playerRef: r,
                  onTap: () => onPick(r),
                  onFavorite: (shown) => _addFavorite(context, ref, r, shown),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A section's title, in the app's section-label style, with its quiet
/// "Clear" at the right.
class _ListHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onClear;
  const _ListHeader({
    required this.icon,
    required this.label,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return SectionLabel(
      icon: icon,
      label: label,
      trailing: TextButton(
        onPressed: onClear,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.sm),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          'Clear',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      ),
    );
  }
}

/// What shows behind a favorite as it is swiped away.
class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppTheme.md),
      decoration: BoxDecoration(
        color: AppTheme.red.withAlpha(25),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: const Icon(Icons.delete_outline, color: AppTheme.red),
    );
  }
}

/// A player as a card: rank badge, name, platform and rank, RP. A favorite is
/// the same card as a recent lookup; the recent one has a star to save it.
class _PlayerCard extends ConsumerWidget {
  final PlayerRef playerRef;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// When set, a star at the end of the card that saves the player. Told what
  /// the card is showing of them, if anything.
  final ValueChanged<PlayerSnapshot?>? onFavorite;

  const _PlayerCard({
    required this.playerRef,
    required this.onTap,
    this.onLongPress,
    this.onFavorite,
  });

  String _sessionKey() {
    if (playerRef.uid != null && playerRef.uid!.isNotEmpty) {
      return playerRef.uid!;
    }
    return playerSessionKey(playerRef.platform, playerRef.query);
  }

  /// The newest the cache or the favorite itself has of the player, however
  /// old: a card with old figures and their age says more than a blank one.
  PlayerSnapshot? _lastKnown(WidgetRef ref) {
    final byUid = playerRef.hasUid;
    final cached = ref
        .watch(playerServiceProvider)
        .getCachedStats(
          byUid ? playerRef.uid! : playerRef.query,
          playerRef.platform,
          searchByUid: byUid,
          allowStale: true,
        );
    final fromCache = cached == null
        ? null
        : PlayerSnapshot.of(cached.data, at: cached.staleAt);
    final kept = playerRef.snapshot;
    if (fromCache == null || kept == null) return fromCache ?? kept;
    return kept.savedAt.isAfter(fromCache.savedAt) ? kept : fromCache;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final synced = ref.watch(sessionRefreshedProvider).contains(_sessionKey());

    // What is known of the player, and how far to trust it: this session's
    // lookup once it has run, otherwise whatever was kept.
    ApiResult<PlayerStats>? live;
    var failed = false;
    if (synced) {
      final byUid = playerRef.hasUid;
      final statsAsync = ref.watch(
        searchPlayerProvider((
          query: byUid ? playerRef.uid! : playerRef.query,
          platform: playerRef.platform,
          searchByUid: byUid,
        )),
      );
      live = statsAsync.whenOrNull(data: (result) => result);
      failed = statsAsync.hasError;
    }
    final shown = live != null
        ? PlayerSnapshot.of(live.data, at: live.staleAt)
        : _lastKnown(ref);
    final age = live == null && shown != null ? _ageOf(shown) : null;

    // Presence is only known from a lookup made this session.
    final dot = failed
        ? AppTheme.red
        : live != null
        ? playerPresenceColor(live.data)
        : AppTheme.muted;

    return Material(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(color: AppTheme.surface2),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.md,
            vertical: AppTheme.sm + 2,
          ),
          child: Row(
            children: [
              _Avatar(
                rankAsset: shown == null
                    ? null
                    : rankAssetPathFor(shown.rank, shown.rankScore),
                presence: dot,
              ),
              const SizedBox(width: AppTheme.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shown?.name ?? playerRef.query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _Subtitle(
                      platform: playerRef.platform,
                      rank: shown == null
                          ? null
                          : rankLabelFor(shown.rank, shown.rankScore),
                      age: age,
                      failed: failed,
                    ),
                  ],
                ),
              ),
              if (shown != null) ...[
                const SizedBox(width: AppTheme.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatNumber(shown.rankScore),
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Text('RP', style: AppTheme.caption),
                  ],
                ),
              ],
              if (onFavorite != null) ...[
                const SizedBox(width: AppTheme.xs),
                IconButton(
                  icon: const Icon(Icons.star_border, color: AppTheme.accent),
                  tooltip: 'Add to favorites',
                  onPressed: () => onFavorite!(shown),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How old [shown] is, once that is worth saying: a day or more.
String? _ageOf(PlayerSnapshot shown) =>
    DateTime.now().difference(shown.savedAt) >= const Duration(days: 1)
    ? timeAgo(shown.savedAt)
    : null;

/// A favorite's rank badge, with its presence dot on the corner. Without a
/// rank to show (nothing looked up yet), a plain person icon holds the place.
class _Avatar extends StatelessWidget {
  final String? rankAsset;
  final Color presence;
  const _Avatar({required this.rankAsset, required this.presence});

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: rankAsset == null
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_outline,
                      color: AppTheme.muted,
                      size: 22,
                    ),
                  )
                : RankBadge(assetPath: rankAsset, size: _size),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.surface, width: 2),
              ),
              child: StatusDot(color: presence, size: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// The platform's icon and name, then the rank.
class _Subtitle extends StatelessWidget {
  final String platform;
  final String? rank;

  /// How old the figures are, when old enough to say.
  final String? age;
  final bool failed;
  const _Subtitle({
    required this.platform,
    required this.rank,
    required this.age,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final icon = platformIconFor(platform);
    return Row(
      children: [
        FaIcon(icon.icon, size: 11, color: icon.color),
        const SizedBox(width: AppTheme.xs + 2),
        Flexible(
          child: Text(
            failed
                ? 'Failed to load'
                : [ApiConstants.labelFor(platform), ?rank, ?age].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: failed
                ? const TextStyle(color: AppTheme.red, fontSize: 12)
                : AppTheme.caption,
          ),
        ),
      ],
    );
  }
}
