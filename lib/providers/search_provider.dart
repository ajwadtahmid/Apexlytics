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
import 'settings_provider.dart';

/// A reference to a previously searched player, used as both a favorites entry
/// and a search parameter. Always prefer UID-based lookups when [hasUid] is true,
/// since UIDs are stable across name changes.
class PlayerRef {
  final String query;
  final String platform;
  final String? uid;
  final bool searchedByUid;

  const PlayerRef({
    required this.query,
    required this.platform,
    this.uid,
    this.searchedByUid = false,
  });

  /// True when a UID is available for this player, regardless of how they were
  /// originally searched. Prefer UID-based lookups whenever this is true.
  bool get hasUid => uid?.isNotEmpty ?? false;

  Map<String, dynamic> toJson() => {
    'query': query,
    'platform': platform,
    'uid': uid,
    if (searchedByUid) 'byUid': true,
  };

  factory PlayerRef.fromJson(Map<String, dynamic> json) => PlayerRef(
    query: json['query'] as String? ?? '',
    platform: json['platform'] as String? ?? ApiConstants.defaultPlatform,
    uid: json['uid'] as String?,
    searchedByUid: json['byUid'] as bool? ?? false,
  );

  // searchedByUid is intentionally excluded from equality and hash: two entries for
  // the same player deduplicate regardless of how they were searched (by name or UID).
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

class SearchState {
  final List<PlayerRef> favorites;

  const SearchState({this.favorites = const []});

  SearchState copyWith({List<PlayerRef>? favorites}) {
    return SearchState(favorites: favorites ?? this.favorites);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchState && listEquals(other.favorites, favorites);

  @override
  int get hashCode => Object.hashAll(favorites);
}

class SearchNotifier extends Notifier<SearchState> {
  /// Oldest favourites are evicted once the list grows past this — matches
  /// the spirit of the 5-profile cap, scaled up since favourites are cheaper.
  static const int maxFavorites = 20;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  SearchState build() {
    return SearchState(favorites: _load(_prefs, PrefsKeys.searchFavorites));
  }

  static List<PlayerRef> _load(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.getString(key) ?? '[]';
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(PlayerRef.fromJson)
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> _save(String key, List<PlayerRef> list) async {
    await _prefs.setString(
      key,
      jsonEncode(list.map((playerRef) => playerRef.toJson()).toList()),
    );
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
          );
          changed = true;
        }
      }
    }
    if (!changed) return;
    await _save(PrefsKeys.searchFavorites, favorites);
    state = state.copyWith(favorites: favorites);
  }

  Future<void> toggleFavorite(PlayerRef playerRef) async {
    final favorites = List<PlayerRef>.from(state.favorites);
    final idx = favorites.indexWhere((f) {
      // Prefer UID matching when both entries have a UID (stable across renames).
      if (playerRef.hasUid && f.hasUid) return f.uid == playerRef.uid;
      // Otherwise (neither has a UID, or only one does) fall back to a
      // case-insensitive name+platform match, so the same player can't be
      // favorited twice under a stale casing or before syncDisplayName
      // enriches one side with a UID.
      return f.platform == playerRef.platform &&
          f.query.toLowerCase() == playerRef.query.toLowerCase();
    });
    if (idx >= 0) {
      favorites.removeAt(idx);
    } else {
      favorites.insert(0, playerRef);
      if (favorites.length > maxFavorites) {
        favorites.removeLast();
      }
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
