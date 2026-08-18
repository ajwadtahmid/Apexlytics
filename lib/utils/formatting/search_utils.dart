import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/api_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/player_service.dart';
import '../app_logger.dart';

String playerSessionKey(String platform, String query) => '$platform:$query';

/// Fetches fresh stats for a player (bypassing the cache-first provider path),
/// invalidates [searchPlayerProvider] so it reads the updated disk cache, then
/// marks the player as synced in [sessionRefreshedProvider].
///
/// Silently skipped (returns true, as if it had succeeded) if [query] was
/// refreshed too recently — see [refreshCooldownProvider]. Otherwise returns
/// true on success, false if the network request failed.
Future<bool> refreshAndMarkSynced(
  WidgetRef ref,
  PlayerService service,
  String query,
  String platform,
  bool byUid,
) async {
  final params = (query: query, platform: platform, searchByUid: byUid);
  if (!ref
      .read(refreshCooldownProvider)
      .tryFire(playerSessionKey(platform, query))) {
    return true;
  }
  try {
    // Call service directly to force a network fetch, bypassing the
    // cache-first path in searchPlayerProvider.
    if (byUid) {
      await service.getPlayerStatsByUid(query.trim(), platform);
    } else {
      await service.getPlayerStats(query.trim(), platform);
    }

    // Always invalidate so the provider reflects the latest disk cache,
    // whether the response was fresh or a stale fallback.
    ref.invalidate(searchPlayerProvider(params));
    await ref.read(searchPlayerProvider(params).future);

    // Mark this player as synced so the favorites list shows live status.
    final stats = ref
        .read(searchPlayerProvider(params))
        .whenOrNull(data: (r) => r.data);
    final key = (stats != null && stats.uid.isNotEmpty)
        ? stats.uid
        : playerSessionKey(platform, query);
    ref.read(sessionRefreshedProvider.notifier).add(key);
    return true;
  } catch (e) {
    log.w('Player refresh failed', error: e);
    return false;
  }
}
