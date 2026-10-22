/// Search state management and favorites persistence.
///
/// Maintains a persisted list of favorite players (UIDs + display names).
/// When syncing player data, automatically enriches name-based entries with
/// UIDs to ensure stable lookups across name changes.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../constants/prefs_keys.dart';
import '../models/player_stats.dart';
import '../utils/error_messages.dart' show AppException;
import 'settings_provider.dart';

/// What a favorite's card shows of a player (name, rank and RP) as of the last
/// time they were looked up. Kept with the favorite so the card still has
/// something to show once the cached response has expired or been evicted.
class PlayerSnapshot {
  final String name;
  final String rank;
  final int rankScore;
  final DateTime savedAt;

  const PlayerSnapshot({
    required this.name,
    required this.rank,
    required this.rankScore,
    required this.savedAt,
  });

  /// [at] is when [stats] were fetched; now when omitted. Kept to the
  /// millisecond, as it is saved, so a snapshot equals its saved copy.
  factory PlayerSnapshot.of(PlayerStats stats, {DateTime? at}) =>
      PlayerSnapshot(
        name: stats.name,
        rank: stats.rank,
        rankScore: stats.rankScore,
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          (at ?? DateTime.now()).millisecondsSinceEpoch,
        ),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'rank': rank,
    'rp': rankScore,
    'at': savedAt.millisecondsSinceEpoch,
  };

  /// Null for anything that isn't a whole snapshot, so a damaged entry reads
  /// as having none.
  static PlayerSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final rank = json['rank'];
    final rp = json['rp'];
    final at = json['at'];
    if (name is! String || rank is! String || rp is! num || at is! num) {
      return null;
    }
    return PlayerSnapshot(
      name: name,
      rank: rank,
      rankScore: rp.toInt(),
      savedAt: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerSnapshot &&
          other.name == name &&
          other.rank == rank &&
          other.rankScore == rankScore &&
          other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(name, rank, rankScore, savedAt);
}

/// A reference to a previously searched player, used as both a favorites entry
/// and a search parameter. Always prefer UID-based lookups when [hasUid] is true,
/// since UIDs are stable across name changes.
class PlayerRef {
  final String query;
  final String platform;
  final String? uid;
  final bool searchedByUid;

  /// The last stats seen for a favorite; null for recents and for favorites
  /// saved before this was kept.
  final PlayerSnapshot? snapshot;

  const PlayerRef({
    required this.query,
    required this.platform,
    this.uid,
    this.searchedByUid = false,
    this.snapshot,
  });

  PlayerRef withSnapshot(PlayerSnapshot? snapshot) => PlayerRef(
    query: query,
    platform: platform,
    uid: uid,
    searchedByUid: searchedByUid,
    snapshot: snapshot,
  );

  /// True when a UID is available for this player, regardless of how they were
  /// originally searched. Prefer UID-based lookups whenever this is true.
  bool get hasUid => uid?.isNotEmpty ?? false;

  Map<String, dynamic> toJson() => {
    'query': query,
    'platform': platform,
    'uid': uid,
    if (searchedByUid) 'byUid': true,
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
  };

  factory PlayerRef.fromJson(Map<String, dynamic> json) => PlayerRef(
    query: json['query'] as String? ?? '',
    platform: json['platform'] as String? ?? ApiConstants.defaultPlatform,
    uid: json['uid'] as String?,
    searchedByUid: json['byUid'] as bool? ?? false,
    snapshot: PlayerSnapshot.fromJson(json['snapshot']),
  );

  // searchedByUid and snapshot are intentionally excluded from equality and
  // hash: two entries for the same player deduplicate regardless of how they
  // were searched (by name or UID) or what was last seen of them.
  // [SearchState] compares snapshots itself, so an update still reaches the
  // favorites list.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerRef &&
          other.query == query &&
          other.platform == platform &&
          other.uid == uid;

  @override
  int get hashCode => Object.hash(query, platform, uid);
}

/// Whether [a] and [b] are the same player: by UID when both have one,
/// otherwise by platform and case-insensitive name.
bool isSamePlayer(PlayerRef a, PlayerRef b) {
  if (a.hasUid && b.hasUid) return a.uid == b.uid;
  return a.platform == b.platform &&
      a.query.toLowerCase() == b.query.toLowerCase();
}

class SearchState {
  final List<PlayerRef> favorites;

  /// Players looked up recently, newest first.
  final List<PlayerRef> recents;

  const SearchState({this.favorites = const [], this.recents = const []});

  SearchState copyWith({List<PlayerRef>? favorites, List<PlayerRef>? recents}) {
    return SearchState(
      favorites: favorites ?? this.favorites,
      recents: recents ?? this.recents,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchState &&
          _sameFavorites(other.favorites, favorites) &&
          listEquals(other.recents, recents);

  static bool _sameFavorites(List<PlayerRef> a, List<PlayerRef> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i] || a[i].snapshot != b[i].snapshot) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll([for (final f in favorites) Object.hash(f, f.snapshot)]),
    Object.hashAll(recents),
  );
}

class SearchNotifier extends Notifier<SearchState> {
  /// The most favourites that can be saved. Adding past it is refused (see
  /// [toggleFavorite]) rather than silently evicting the oldest one.
  static const int maxFavorites = 20;

  static const _favoritesFull = AppException(
    'You can save up to $maxFavorites favorites. Remove one to add another.',
  );

  /// How many recent lookups are kept.
  static const int maxRecents = 5;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  SearchState build() {
    return SearchState(
      favorites: _load(_prefs, PrefsKeys.searchFavorites),
      recents: _load(_prefs, PrefsKeys.recentSearches),
    );
  }

  static List<PlayerRef> _load(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.getString(key) ?? '[]';
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PlayerRef.fromJson)
          .toList();
    } catch (e) {
      // Well-formed-but-wrong-shape JSON throws TypeError, not
      // FormatException — see rp_snapshot_storage._parseSnapshots.
      return [];
    }
  }

  Future<void> _save(String key, List<PlayerRef> list) async {
    await _prefs.setString(
      key,
      jsonEncode(list.map((playerRef) => playerRef.toJson()).toList()),
    );
  }

  /// Puts [playerRef] first in the recent lookups, dropping an earlier entry
  /// for the same player and anything past [maxRecents].
  Future<void> recordRecent(PlayerRef playerRef) async {
    if (playerRef.query.isEmpty) return;
    final recents = [
      playerRef,
      ...state.recents.where((r) => !isSamePlayer(r, playerRef)),
    ].take(maxRecents).toList();
    if (listEquals(recents, state.recents)) return;
    await _save(PrefsKeys.recentSearches, recents);
    state = state.copyWith(recents: recents);
  }

  Future<void> clearRecents() async {
    await _prefs.remove(PrefsKeys.recentSearches);
    state = state.copyWith(recents: []);
  }

  Future<void> clearFavorites() async {
    await _prefs.remove(PrefsKeys.searchFavorites);
    state = state.copyWith(favorites: []);
  }

  /// Updates the stored display name (query) and UID for matching favorites.
  /// Matches by UID (for entries already resolved) OR by display name (for
  /// name-based entries that don't yet have a UID, so they get enriched).
  Future<void> syncDisplayName(String uid, String canonicalName) async {
    if (uid.isEmpty || canonicalName.isEmpty) return;
    final favorites = List<PlayerRef>.from(state.favorites);
    bool changed = false;
    for (int i = 0; i < favorites.length; i++) {
      final f = favorites[i];
      final uidMatch = f.uid == uid;
      // Enrich name-based entries: match on display name so they get a UID.
      final nameEnrich =
          f.uid == null && f.query.toLowerCase() == canonicalName.toLowerCase();
      if (uidMatch || nameEnrich) {
        if (f.uid != uid || f.query != canonicalName) {
          favorites[i] = PlayerRef(
            query: canonicalName,
            platform: f.platform,
            uid: uid,
            searchedByUid: f.searchedByUid,
            snapshot: f.snapshot,
          );
          changed = true;
        }
      }
    }
    if (!changed) return;
    await _save(PrefsKeys.searchFavorites, favorites);
    state = state.copyWith(favorites: favorites);
  }

  /// Records [stats], fetched at [at] (now when omitted), as what is known of
  /// the matching favorite. Does nothing when that player isn't a favorite, or
  /// when a newer snapshot is already kept, so a cached read never replaces a
  /// live one.
  Future<void> updateSnapshot(
    String platform,
    PlayerStats stats, {
    DateTime? at,
  }) async {
    if (stats.uid.isEmpty) return;
    final snapshot = PlayerSnapshot.of(stats, at: at);
    final favorites = List<PlayerRef>.from(state.favorites);
    final idx = _favoriteIndex(
      favorites,
      PlayerRef(query: stats.name, platform: platform, uid: stats.uid),
    );
    if (idx < 0) return;
    final kept = favorites[idx].snapshot;
    if (kept != null && !snapshot.savedAt.isAfter(kept.savedAt)) return;
    favorites[idx] = favorites[idx].withSnapshot(snapshot);
    await _save(PrefsKeys.searchFavorites, favorites);
    state = state.copyWith(favorites: favorites);
  }

  static int _favoriteIndex(List<PlayerRef> favorites, PlayerRef playerRef) =>
      favorites.indexWhere((f) {
        // Prefer UID matching when both entries have a UID (stable across
        // renames).
        if (playerRef.hasUid && f.hasUid) return f.uid == playerRef.uid;
        // Otherwise (neither has a UID, or only one does) fall back to a
        // case-insensitive name+platform match, so the same player can't be
        // favorited twice under a stale casing or before syncDisplayName
        // enriches one side with a UID.
        return f.platform == playerRef.platform &&
            f.query.toLowerCase() == playerRef.query.toLowerCase();
      });

  /// Takes [playerRef] off the favourites. The list changes before the save
  /// finishes, which a swiped-away row needs: it must be gone from the list on
  /// the frame it is dismissed.
  Future<void> removeFavorite(PlayerRef playerRef) async {
    final favorites = List<PlayerRef>.from(state.favorites);
    final idx = _favoriteIndex(favorites, playerRef);
    if (idx < 0) return;
    favorites.removeAt(idx);
    state = state.copyWith(favorites: favorites);
    await _save(PrefsKeys.searchFavorites, favorites);
  }

  /// Puts a removed favourite back at [index] (clamped), for an Undo. Does
  /// nothing if that player was saved again meanwhile; throws like
  /// [toggleFavorite] when the list has filled up in the meantime.
  Future<void> restoreFavorite(PlayerRef playerRef, int index) async {
    final favorites = List<PlayerRef>.from(state.favorites);
    if (_favoriteIndex(favorites, playerRef) >= 0) return;
    if (favorites.length >= maxFavorites) {
      throw _favoritesFull;
    }
    favorites.insert(index.clamp(0, favorites.length), playerRef);
    state = state.copyWith(favorites: favorites);
    await _save(PrefsKeys.searchFavorites, favorites);
  }

  /// Adds [playerRef] as a favourite, or removes it if already saved. Throws
  /// an [AppException] when adding would pass [maxFavorites]; removing is
  /// always allowed.
  Future<void> toggleFavorite(PlayerRef playerRef) async {
    final favorites = List<PlayerRef>.from(state.favorites);
    final idx = _favoriteIndex(favorites, playerRef);
    if (idx >= 0) {
      favorites.removeAt(idx);
    } else {
      if (favorites.length >= maxFavorites) {
        throw _favoritesFull;
      }
      favorites.insert(0, playerRef);
    }
    await _save(PrefsKeys.searchFavorites, favorites);
    state = state.copyWith(favorites: favorites);
  }
}

/// Persisted list of favorited players. Toggle favorites via
/// `ref.read(searchStateProvider.notifier).toggleFavorite(playerRef)`.
final searchStateProvider = NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);
