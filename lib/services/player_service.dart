import '../models/player_stats.dart';
import '../utils/app_logger.dart';
import '../utils/error_messages.dart';
import 'api_service.dart';

/// Result from a name-to-UID resolution. The [uid] is stable; [name] reflects
/// the canonical display name returned by the API.
class PlayerUidResult {
  final String name;
  final String uid;
  final String avatar;

  PlayerUidResult({
    required this.name,
    required this.uid,
    required this.avatar,
  });

  factory PlayerUidResult.fromJson(Map<String, dynamic> json) {
    return PlayerUidResult(
      name: json['name'] as String? ?? 'Unknown',
      uid: json['uid']?.toString() ?? '',
      avatar: json['avatar'] as String? ?? '',
    );
  }
}

/// Domain service for all player-related API calls. Prefer [getPlayerStatsByUid]
/// over [getPlayerStats] whenever a UID is available — UIDs survive name changes.
class PlayerService {
  final ApiService _api;
  PlayerService(this._api);

  /// Normalizes a name for cache-key purposes, matching [playerRefreshKey]'s
  /// cooldown key - otherwise "Bob" and "bob" produce two cache entries
  /// sharing one cooldown. Only the key is normalized; upstream queries keep
  /// the user's casing.
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
      '/player',
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
    final endpoint = searchByUid ? '/player/uid' : '/player';
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
    return ApiResult(
      PlayerStats.fromJson(result.data),
      staleAt: result.staleAt,
    );
  }

  /// Fetches stats by UID. This is the preferred lookup path for saved profiles.
  Future<ApiResult<PlayerStats>> getPlayerStatsByUid(
    String uid,
    String platform,
  ) async {
    log.d('Fetching player stats by UID [$platform]');
    final result = await _api.get(
      '/player/uid',
      params: {'uid': uid, 'platform': platform},
    );
    log.d('Player stats fetched by UID, stale=${result.staleAt != null}');
    return ApiResult(
      PlayerStats.fromJson(result.data),
      staleAt: result.staleAt,
    );
  }

  // nameToUid is only ever called on user action. noCache:true prevents a
  // stale UID from being served after a player renames their account.
  Future<PlayerUidResult> nameToUid(String playerName, String platform) async {
    final result = await _api.get(
      '/nametouid',
      params: {'player': playerName.trim(), 'platform': platform},
      noCache: true,
    );
    final lookup = PlayerUidResult.fromJson(result.data);
    if (lookup.uid.isEmpty) {
      throw const AppException(
        'Player not found. Check the name and platform.',
      );
    }
    return lookup;
  }
}
