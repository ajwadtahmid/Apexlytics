import '../constants/api_constants.dart';
import '../models/player_stats.dart';
import '../utils/app_logger.dart';
import 'api_service.dart';

/// Domain service for all player-related API calls. Prefer [getPlayerStatsByUid]
/// over [getPlayerStats] whenever a UID is available — UIDs survive name changes.
class PlayerService {
  final ApiService _api;
  PlayerService(this._api);

  /// Parsed cache reads, valid while the cache entry's save time is unchanged,
  /// so rebuilding the favourites list doesn't re-parse every payload.
  final Map<String, (DateTime savedAt, PlayerStats stats)> _parsed = {};
  static const _maxParsed = 50;

  /// Normalizes a name for both the upstream query and the cache key.
  /// Upstream name lookups are case-insensitive, so "Bob" and "bob" are the
  /// same player — sending the lowercased form for both means they also share
  /// one cache entry and one cooldown instead of two.
  static String _cacheName(String playerName) =>
      playerName.trim().toLowerCase();

  /// Fetches stats by display name. Avoid when a UID is known; name lookups break
  /// if the player renames.
  Future<ApiResult<PlayerStats>> getPlayerStats(
    String playerName,
    String platform,
  ) async {
    log.d('Fetching player stats by name [$platform]');
    final result = await _api.get(
      ApiConstants.playerPath,
      params: {'player': _cacheName(playerName), 'platform': platform},
    );
    log.d('Player stats fetched by name, stale=${result.staleAt != null}');
    return ApiResult(
      PlayerStats.fromJson(result.data),
      staleAt: result.staleAt,
    );
  }

  /// Returns cached stats without a network request, or null if no cache.
  /// When [searchByUid] is true, looks up the UID-based cache endpoint.
  /// When [searchByUid] is false, looks up the name-based cache endpoint.
  ApiResult<PlayerStats>? getCachedStats(
    String query,
    String platform, {
    bool searchByUid = false,
  }) {
    log.d('Cache lookup: byUid=$searchByUid [$platform]');
    final endpoint = searchByUid
        ? ApiConstants.playerUidPath
        : ApiConstants.playerPath;
    // Must build the key exactly as getPlayerStats/getPlayerStatsByUid do, or
    // a warm cache reads as a miss.
    final params = searchByUid
        ? {'uid': query, 'platform': platform}
        : {'player': _cacheName(query), 'platform': platform};

    final result = _api.loadCached(endpoint, params: params);
    if (result == null) {
      log.d('Cache miss');
      return null;
    }
    log.d('Cache hit, stale=${result.staleAt != null}');
    final savedAt = result.staleAt;
    final memoKey = '$endpoint|${params.values.join('|')}';
    final memo = _parsed[memoKey];
    if (memo != null && savedAt != null && memo.$1 == savedAt) {
      return ApiResult(memo.$2, staleAt: savedAt);
    }
    final stats = PlayerStats.fromJson(result.data);
    if (savedAt != null) {
      if (_parsed.length >= _maxParsed) _parsed.clear();
      _parsed[memoKey] = (savedAt, stats);
    }
    return ApiResult(stats, staleAt: savedAt);
  }

  /// Fetches stats by UID. This is the preferred lookup path for saved profiles.
  Future<ApiResult<PlayerStats>> getPlayerStatsByUid(
    String uid,
    String platform,
  ) async {
    log.d('Fetching player stats by UID [$platform]');
    final result = await _api.get(
      ApiConstants.playerUidPath,
      params: {'uid': uid, 'platform': platform},
    );
    log.d('Player stats fetched by UID, stale=${result.staleAt != null}');
    return ApiResult(
      PlayerStats.fromJson(result.data),
      staleAt: result.staleAt,
    );
  }
}
