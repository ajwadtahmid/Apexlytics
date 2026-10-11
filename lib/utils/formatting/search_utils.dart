import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/api_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/player_service.dart';
import '../app_logger.dart';

String playerSessionKey(String platform, String query) => '$platform:$query';

/// Cooldown key for "fetch this player's stats", fired by the lookup form and
/// by the favorites and result-page refreshes. Trims and lowercases [query] so
/// one player maps to a single cooldown window however it was typed.
///
/// [playerSessionKey] is the separate identity key the synced badge reads.
String playerRefreshKey(String platform, String query) =>
    '$platform:${query.trim().toLowerCase()}';

/// Fetches fresh stats for a player (bypassing the cache-first provider path),
/// invalidates [searchPlayerProvider] so it serves that result (see
/// [liveSearchResultProvider]), then marks the player as synced in
/// [sessionRefreshedProvider].
///
/// Skips the fetch when [query] was refreshed too recently — see
/// [refreshCooldownProvider] — and in that case still returns true and still
/// marks the player synced, a recent fetch having already refreshed it.
/// Returns false when nothing was fetched: the request failed, or failed and
/// the cached copy was served instead. In that case the player is not marked
/// synced.
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
      .tryFire(playerRefreshKey(platform, query))) {
    // The same key _FavoriteTile reads the badge under, built from the
    // arguments; reading searchPlayerProvider here would start the fetch this
    // branch just suppressed.
    ref
        .read(sessionRefreshedProvider.notifier)
        .add(byUid ? query.trim() : playerSessionKey(platform, query));
    return true;
  }
  try {
    // Call service directly to force a network fetch, bypassing the
    // cache-first path in searchPlayerProvider.
    final result = byUid
        ? await service.getPlayerStatsByUid(query.trim(), platform)
        : await service.getPlayerStats(query.trim(), platform);

    // A live answer goes to the provider as it is: re-reading the cache entry
    // it just wrote would come back with a save time and show as stale. A
    // stale fallback is left to the cache read, which keeps it marked stale.
    ref
        .read(liveSearchResultProvider(params).notifier)
        .set(result.staleAt == null ? result : null);

    // Always invalidate so the provider reflects the latest result, whether
    // the response was fresh or a stale fallback.
    ref.invalidate(searchPlayerProvider(params));
    await ref.read(searchPlayerProvider(params).future);

    // The request failed and the service fell back to the cached copy:
    // nothing was fetched, so the player is not synced.
    if (result.staleAt != null) return false;

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
