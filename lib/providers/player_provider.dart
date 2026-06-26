import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_stats.dart';
import '../services/api_service.dart';
import '../services/player_service.dart';
import '../utils/app_logger.dart';
import 'api_provider.dart';
import 'settings_provider.dart';

typedef PlayerSearchQuery = ({String query, String platform, bool searchByUid});

/// One-shot stats fetch used by the search flow. Returns disk-cached data
/// immediately if available so there is no loading spinner for returning
/// visitors. The user can force a live fetch via the refresh button, which
/// calls the service directly and then invalidates this provider.
final searchPlayerProvider =
    FutureProvider.autoDispose.family<ApiResult<PlayerStats>, PlayerSearchQuery>((
      ref,
      params,
    ) async {
      final (:query, :platform, :searchByUid) = params;
      final service = ref.watch(playerServiceProvider);

      final cached = service.getCachedStats(
        query.trim(),
        platform,
        searchByUid: searchByUid,
      );
      if (cached != null) return cached;

      if (searchByUid) {
        return service.getPlayerStatsByUid(query.trim(), platform);
      }
      return service.getPlayerStats(query.trim(), platform);
    });

/// Tracks which player UIDs (or "platform:query" keys) were manually synced
/// this session. Used by the search screen to show grey dots until the user
/// has explicitly refreshed a favorite.
final sessionRefreshedProvider =
    NotifierProvider<_SessionRefreshedNotifier, Set<String>>(_SessionRefreshedNotifier.new);

class _SessionRefreshedNotifier extends Notifier<Set<String>> {
  static const _maxSize = 100;

  @override
  Set<String> build() => {};

  void add(String key) {
    if (state.contains(key)) return;
    final next = {...state, key};
    // LRU eviction: LinkedHashSet preserves insertion order. When the set exceeds
    // _maxSize, drop entries from the start (oldest), keeping only the most recent.
    // skip() is O(n) on a set, but acceptable for _maxSize (100 entries).
    state = next.length > _maxSize
        ? LinkedHashSet<String>.from(next.skip(next.length - _maxSize))
        : next;
  }
}

/// Stats for the saved "my player" profile. On first load, returns cached data
/// immediately (no shimmer) and kicks off a silent background refresh. If the
/// refresh fails, the stale banner is shown but the cached data remains visible.
final myPlayerStatsProvider =
    AsyncNotifierProvider<MyPlayerStatsNotifier, ApiResult<PlayerStats?>>(
      MyPlayerStatsNotifier.new,
    );

class MyPlayerStatsNotifier extends AsyncNotifier<ApiResult<PlayerStats?>> {
  // Guards against stale updates when the user switches profiles mid-fetch: if
  // build() runs again before _refreshSilent completes, the outdated fetch will
  // check its generation against the current value and discard its result.
  int _buildGeneration = 0;
  bool _refreshing = false;

  @override
  Future<ApiResult<PlayerStats?>> build() async {
    final generation = ++_buildGeneration;

    final isSet = ref.watch(playerSettingsProvider.select((s) => s.isPlayerSet));
    if (!isSet) return const ApiResult(null);

    final uid = ref.watch(playerSettingsProvider.select((s) => s.uid));
    final platform = ref.watch(playerSettingsProvider.select((s) => s.platform));
    final service = ref.watch(playerServiceProvider);
    final cached = service.getCachedStats(uid, platform, searchByUid: true);

    if (cached != null) {
      _refreshSilent(service, uid, platform, generation);
      return ApiResult<PlayerStats?>(cached.data, staleAt: cached.staleAt);
    }

    return service
        .getPlayerStatsByUid(uid, platform)
        .then((r) => ApiResult<PlayerStats?>(r.data, staleAt: r.staleAt));
  }

  /// Silent background refresh — updates state without going through AsyncLoading.
  /// Can also be called externally (e.g. from _StatsViewState) as a belt-and-
  /// suspenders fallback when stale data is showing.
  Future<void> softRefresh() async {
    final settings = ref.read(playerSettingsProvider);
    if (!settings.isPlayerSet) return;
    final service = ref.read(playerServiceProvider);
    await _refreshSilent(service, settings.uid, settings.platform, _buildGeneration);
  }

  Future<void> _refreshSilent(
    PlayerService service,
    String uid,
    String platform,
    int generation,
  ) async {
    if (_refreshing) return;
    // Set synchronously before the first await — Dart's single-threaded model
    // guarantees no other caller can interleave before this flag is set.
    _refreshing = true;
    try {
      final fresh = await service.getPlayerStatsByUid(uid, platform);
      // Only update if we are still in the same build cycle and the notifier
      // has not been disposed (ref.mounted guards against disposed-notifier throws).
      if (_buildGeneration == generation && ref.mounted) {
        state = AsyncData(ApiResult<PlayerStats?>(fresh.data, staleAt: fresh.staleAt));
      }
    } catch (e) {
      // Only log if the request is still relevant (generation hasn't advanced).
      // If it has, the user switched profiles and this error is stale.
      if (_buildGeneration == generation) {
        log.w('Silent refresh failed', error: e);
      }
    } finally {
      _refreshing = false;
    }
  }
}
