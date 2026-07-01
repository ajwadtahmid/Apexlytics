import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../constants/prefs_keys.dart';
import '../utils/app_logger.dart';
import '../utils/formatting/json_utils.dart';

/// Must be overridden in `main` before `runApp` via `ProviderScope(overrides: [...])`.
/// Provides a synchronous `SharedPreferences` instance to all notifiers that
/// persist settings without async initialization boilerplate.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main',
  );
});

// ── Player profile ────────────────────────────────────────────────────────────

/// A single saved player account (name + UID + platform). Up to 3 profiles are
/// stored under one app installation via [PlayerSettingsNotifier].
class PlayerProfile {
  final String name;
  final String uid;
  final String platform;

  const PlayerProfile({
    required this.name,
    required this.uid,
    this.platform = ApiConstants.defaultPlatform,
  });

  bool get isSet => uid.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    'uid': uid,
    'platform': platform,
  };

  factory PlayerProfile.fromJson(Map<String, dynamic> json) => PlayerProfile(
    name: json['name'] as String? ?? '',
    uid: json['uid'] as String? ?? '',
    platform: json['platform'] as String? ?? ApiConstants.defaultPlatform,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerProfile &&
          other.name == name &&
          other.uid == uid &&
          other.platform == platform;

  @override
  int get hashCode => Object.hash(name, uid, platform);
}

// ── Player settings ───────────────────────────────────────────────────────────

/// Immutable snapshot of all persisted app settings. Mutated exclusively
/// through [PlayerSettingsNotifier] which writes each change to [SharedPreferences]
/// before updating state — no setting is lost on a hot-restart or process kill.
class PlayerSettings {
  final List<PlayerProfile> profiles; // max 3
  final int activeProfileIndex;
  final int statsRefreshMinutes; // 0 = manual only
  final bool compactLegendCards;
  final bool notifyPubsMapRotation;
  final bool notifyRankedMapRotation;
  final bool notifyMixtapeMapRotation;
  final bool notifyWildcardMapRotation;
  final int rankedNotifyMinutesBefore; // 0 = off, else minutes before rotation
  final int pubsNotifyMinutesBefore;
  final int mixtapeNotifyMinutesBefore;
  final int wildcardNotifyMinutesBefore;
  final int defaultTab; // 0=Home 1=Stats 2=Search 3=Settings
  final List<String> favoriteRankedMapNames;
  final List<String> favoritePubsMapNames;

  const PlayerSettings({
    this.profiles = const [],
    this.activeProfileIndex = 0,
    this.statsRefreshMinutes = 0,
    this.compactLegendCards = false,
    this.notifyPubsMapRotation = false,
    this.notifyRankedMapRotation = false,
    this.notifyMixtapeMapRotation = false,
    this.notifyWildcardMapRotation = false,
    this.rankedNotifyMinutesBefore = 0,
    this.pubsNotifyMinutesBefore = 0,
    this.mixtapeNotifyMinutesBefore = 0,
    this.wildcardNotifyMinutesBefore = 0,
    this.defaultTab = 0,
    this.favoriteRankedMapNames = const [],
    this.favoritePubsMapNames = const [],
  });

  PlayerProfile? get activeProfile => activeProfileIndex < profiles.length
      ? profiles[activeProfileIndex]
      : null;

  String get name => activeProfile?.name ?? '';
  String get uid => activeProfile?.uid ?? '';
  String get platform =>
      activeProfile?.platform ?? ApiConstants.defaultPlatform;
  bool get isPlayerSet => activeProfile?.isSet ?? false;

  @override
  // Keep in sync with hashCode below whenever fields are added.
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerSettings &&
          listEquals(other.profiles, profiles) &&
          other.activeProfileIndex == activeProfileIndex &&
          other.statsRefreshMinutes == statsRefreshMinutes &&
          other.compactLegendCards == compactLegendCards &&
          other.notifyPubsMapRotation == notifyPubsMapRotation &&
          other.notifyRankedMapRotation == notifyRankedMapRotation &&
          other.notifyMixtapeMapRotation == notifyMixtapeMapRotation &&
          other.notifyWildcardMapRotation == notifyWildcardMapRotation &&
          other.rankedNotifyMinutesBefore == rankedNotifyMinutesBefore &&
          other.pubsNotifyMinutesBefore == pubsNotifyMinutesBefore &&
          other.mixtapeNotifyMinutesBefore == mixtapeNotifyMinutesBefore &&
          other.wildcardNotifyMinutesBefore == wildcardNotifyMinutesBefore &&
          other.defaultTab == defaultTab &&
          listEquals(other.favoriteRankedMapNames, favoriteRankedMapNames) &&
          listEquals(other.favoritePubsMapNames, favoritePubsMapNames);

  @override
  // Keep in sync with operator== above whenever fields are added.
  int get hashCode => Object.hash(
    Object.hashAll(profiles),
    activeProfileIndex,
    statsRefreshMinutes,
    compactLegendCards,
    notifyPubsMapRotation,
    notifyRankedMapRotation,
    notifyMixtapeMapRotation,
    notifyWildcardMapRotation,
    rankedNotifyMinutesBefore,
    pubsNotifyMinutesBefore,
    mixtapeNotifyMinutesBefore,
    wildcardNotifyMinutesBefore,
    defaultTab,
    Object.hashAll(favoriteRankedMapNames),
    Object.hashAll(favoritePubsMapNames),
  );

  PlayerSettings copyWith({
    List<PlayerProfile>? profiles,
    int? activeProfileIndex,
    int? statsRefreshMinutes,
    bool? compactLegendCards,
    bool? notifyPubsMapRotation,
    bool? notifyRankedMapRotation,
    bool? notifyMixtapeMapRotation,
    bool? notifyWildcardMapRotation,
    int? rankedNotifyMinutesBefore,
    int? pubsNotifyMinutesBefore,
    int? mixtapeNotifyMinutesBefore,
    int? wildcardNotifyMinutesBefore,
    int? defaultTab,
    List<String>? favoriteRankedMapNames,
    List<String>? favoritePubsMapNames,
  }) {
    return PlayerSettings(
      profiles: profiles ?? this.profiles,
      activeProfileIndex: activeProfileIndex ?? this.activeProfileIndex,
      statsRefreshMinutes: statsRefreshMinutes ?? this.statsRefreshMinutes,
      compactLegendCards: compactLegendCards ?? this.compactLegendCards,
      notifyPubsMapRotation:
          notifyPubsMapRotation ?? this.notifyPubsMapRotation,
      notifyRankedMapRotation:
          notifyRankedMapRotation ?? this.notifyRankedMapRotation,
      notifyMixtapeMapRotation:
          notifyMixtapeMapRotation ?? this.notifyMixtapeMapRotation,
      notifyWildcardMapRotation:
          notifyWildcardMapRotation ?? this.notifyWildcardMapRotation,
      rankedNotifyMinutesBefore:
          rankedNotifyMinutesBefore ?? this.rankedNotifyMinutesBefore,
      pubsNotifyMinutesBefore:
          pubsNotifyMinutesBefore ?? this.pubsNotifyMinutesBefore,
      mixtapeNotifyMinutesBefore:
          mixtapeNotifyMinutesBefore ?? this.mixtapeNotifyMinutesBefore,
      wildcardNotifyMinutesBefore:
          wildcardNotifyMinutesBefore ?? this.wildcardNotifyMinutesBefore,
      defaultTab: defaultTab ?? this.defaultTab,
      favoriteRankedMapNames:
          favoriteRankedMapNames ?? this.favoriteRankedMapNames,
      favoritePubsMapNames: favoritePubsMapNames ?? this.favoritePubsMapNames,
    );
  }
}

class PlayerSettingsNotifier extends Notifier<PlayerSettings> {
  static const int maxProfileCount = 3;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  static List<PlayerProfile> _parseProfiles(String? raw) {
    try {
      final list = jsonDecode(raw ?? '[]') as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(PlayerProfile.fromJson)
          .take(maxProfileCount)
          .toList();
    } on FormatException {
      return [];
    }
  }

  @override
  PlayerSettings build() {
    var profiles = _parseProfiles(_prefs.getString(PrefsKeys.profiles));
    var activeIdx = _prefs.getInt(PrefsKeys.activeProfileIndex) ?? 0;

    // Migrate from legacy single-player keys when the profiles key is absent.
    if (profiles.isEmpty && _prefs.containsKey(PrefsKeys.playerName)) {
      final name = _prefs.getString(PrefsKeys.playerName) ?? '';
      final uid = _prefs.getString(PrefsKeys.playerUid) ?? '';
      final platform =
          _prefs.getString(PrefsKeys.playerPlatform) ??
          ApiConstants.defaultPlatform;
      if (name.isNotEmpty || uid.isNotEmpty) {
        profiles = [PlayerProfile(name: name, uid: uid, platform: platform)];
        activeIdx = 0;
        // build() is synchronous so we can't await here. The migration is
        // idempotent — if the write doesn't complete the key stays absent and
        // migration re-runs harmlessly on next launch.
        unawaited(
          _prefs
              .setString(
                PrefsKeys.profiles,
                jsonEncode([profiles.first.toJson()]),
              )
              .catchError((Object e) {
                log.w('Migration persist failed', error: e);
                return false;
              }),
        );
      }
    }

    if (activeIdx >= profiles.length && profiles.isNotEmpty) {
      activeIdx = profiles.length - 1;
    }

    // One-time migration: copy legacy global timing to per-mode keys if needed.
    final legacyMinutes = _prefs.getInt(PrefsKeys.mapNotifyMinutes) ?? 0;
    if (legacyMinutes > 0 &&
        !_prefs.containsKey(PrefsKeys.rankedNotifyMinutes) &&
        !_prefs.containsKey(PrefsKeys.pubsNotifyMinutes) &&
        !_prefs.containsKey(PrefsKeys.mixtapeNotifyMinutes)) {
      unawaited(
        Future.wait([
          _prefs.setInt(PrefsKeys.rankedNotifyMinutes, legacyMinutes),
          _prefs.setInt(PrefsKeys.pubsNotifyMinutes, legacyMinutes),
          _prefs.setInt(PrefsKeys.mixtapeNotifyMinutes, legacyMinutes),
        ]).catchError((Object e) {
          log.w('Per-mode timing migration failed', error: e);
          return <bool>[];
        }),
      );
    }

    return PlayerSettings(
      profiles: profiles,
      activeProfileIndex: activeIdx,
      statsRefreshMinutes: _prefs.getInt(PrefsKeys.statsRefreshMinutes) ?? 0,
      compactLegendCards: _prefs.getBool(PrefsKeys.compactLegendCards) ?? false,
      notifyPubsMapRotation:
          _prefs.getBool(PrefsKeys.notifyPubsMapRotation) ?? false,
      notifyRankedMapRotation:
          _prefs.getBool(PrefsKeys.notifyRankedMapRotation) ?? false,
      notifyMixtapeMapRotation:
          _prefs.getBool(PrefsKeys.notifyMixtapeMapRotation) ?? false,
      notifyWildcardMapRotation:
          _prefs.getBool(PrefsKeys.notifyWildcardMapRotation) ?? false,
      rankedNotifyMinutesBefore:
          _prefs.getInt(PrefsKeys.rankedNotifyMinutes) ?? legacyMinutes,
      pubsNotifyMinutesBefore:
          _prefs.getInt(PrefsKeys.pubsNotifyMinutes) ?? legacyMinutes,
      mixtapeNotifyMinutesBefore:
          _prefs.getInt(PrefsKeys.mixtapeNotifyMinutes) ?? legacyMinutes,
      wildcardNotifyMinutesBefore:
          _prefs.getInt(PrefsKeys.wildcardNotifyMinutes) ?? 0,
      defaultTab: _prefs.getInt(PrefsKeys.defaultTab) ?? 0,
      favoriteRankedMapNames: parseStringList(
        _prefs.getString(PrefsKeys.favoriteRankedMapNames),
      ),
      favoritePubsMapNames: parseStringList(
        _prefs.getString(PrefsKeys.favoritePubsMapNames),
      ),
    );
  }

  Future<void> _saveProfiles(List<PlayerProfile> profiles) async {
    await _prefs.setString(
      PrefsKeys.profiles,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> setPlayer(String name, String uid, String platform) async {
    final profiles = List<PlayerProfile>.from(state.profiles);
    final idx = state.activeProfileIndex;
    final newProfile = PlayerProfile(name: name, uid: uid, platform: platform);
    if (idx < profiles.length) {
      profiles[idx] = newProfile;
    } else {
      profiles.add(newProfile);
    }
    await _saveProfiles(profiles);
    await _prefs.setInt(PrefsKeys.activeProfileIndex, idx);
    state = state.copyWith(profiles: profiles, activeProfileIndex: idx);
  }

  Future<void> setActiveProfileIndex(int index) async {
    if (index < 0 || index >= state.profiles.length) return;
    await _prefs.setInt(PrefsKeys.activeProfileIndex, index);
    state = state.copyWith(activeProfileIndex: index);
  }

  /// Appends a new profile and switches to it.
  Future<void> addProfile(String name, String uid, String platform) async {
    if (state.profiles.length >= maxProfileCount) return;
    final profiles = [
      ...state.profiles,
      PlayerProfile(name: name, uid: uid, platform: platform),
    ];
    final newIdx = profiles.length - 1;
    await _saveProfiles(profiles);
    await _prefs.setInt(PrefsKeys.activeProfileIndex, newIdx);
    state = state.copyWith(profiles: profiles, activeProfileIndex: newIdx);
  }

  /// Updates a specific profile slot without switching the active profile.
  Future<void> updateProfile(
    int index,
    String name,
    String uid,
    String platform,
  ) async {
    if (index < 0 || index >= state.profiles.length) return;
    final profiles = List<PlayerProfile>.from(state.profiles);
    profiles[index] = PlayerProfile(name: name, uid: uid, platform: platform);
    await _saveProfiles(profiles);
    state = state.copyWith(profiles: profiles);
  }

  Future<void> removeProfile(int index) async {
    if (index < 0 || index >= state.profiles.length) return;
    final profiles = List<PlayerProfile>.from(state.profiles)..removeAt(index);
    var activeIdx = state.activeProfileIndex;
    if (profiles.isEmpty) {
      activeIdx = 0;
    } else if (activeIdx >= profiles.length) {
      activeIdx = profiles.length - 1;
    }
    await _saveProfiles(profiles);
    await _prefs.setInt(PrefsKeys.activeProfileIndex, activeIdx);
    state = state.copyWith(profiles: profiles, activeProfileIndex: activeIdx);
  }

  Future<void> _setBool(
    String key,
    bool value,
    PlayerSettings Function(PlayerSettings) update,
  ) async {
    await _prefs.setBool(key, value);
    state = update(state);
  }

  Future<void> _setInt(
    String key,
    int value,
    PlayerSettings Function(PlayerSettings) update,
  ) async {
    await _prefs.setInt(key, value);
    state = update(state);
  }

  Future<void> _setStringList(
    String key,
    List<String> value,
    PlayerSettings Function(PlayerSettings) update,
  ) async {
    await _prefs.setString(key, jsonEncode(value));
    state = update(state);
  }

  Future<void> setStatsRefreshMinutes(int v) => _setInt(
    PrefsKeys.statsRefreshMinutes,
    v,
    (s) => s.copyWith(statsRefreshMinutes: v),
  );

  Future<void> setCompactLegendCards(bool v) => _setBool(
    PrefsKeys.compactLegendCards,
    v,
    (s) => s.copyWith(compactLegendCards: v),
  );

  Future<void> setRankedNotifyMinutesBefore(int v) => _setInt(
    PrefsKeys.rankedNotifyMinutes,
    v,
    (s) => s.copyWith(rankedNotifyMinutesBefore: v),
  );

  Future<void> setPubsNotifyMinutesBefore(int v) => _setInt(
    PrefsKeys.pubsNotifyMinutes,
    v,
    (s) => s.copyWith(pubsNotifyMinutesBefore: v),
  );

  Future<void> setMixtapeNotifyMinutesBefore(int v) => _setInt(
    PrefsKeys.mixtapeNotifyMinutes,
    v,
    (s) => s.copyWith(mixtapeNotifyMinutesBefore: v),
  );

  Future<void> setNotifyPubsMapRotation(bool v) => _setBool(
    PrefsKeys.notifyPubsMapRotation,
    v,
    (s) => s.copyWith(notifyPubsMapRotation: v),
  );

  Future<void> setNotifyRankedMapRotation(bool v) => _setBool(
    PrefsKeys.notifyRankedMapRotation,
    v,
    (s) => s.copyWith(notifyRankedMapRotation: v),
  );

  Future<void> setNotifyMixtapeMapRotation(bool v) => _setBool(
    PrefsKeys.notifyMixtapeMapRotation,
    v,
    (s) => s.copyWith(notifyMixtapeMapRotation: v),
  );

  Future<void> setNotifyWildcardMapRotation(bool v) => _setBool(
    PrefsKeys.notifyWildcardMapRotation,
    v,
    (s) => s.copyWith(notifyWildcardMapRotation: v),
  );

  Future<void> setWildcardNotifyMinutesBefore(int v) => _setInt(
    PrefsKeys.wildcardNotifyMinutes,
    v,
    (s) => s.copyWith(wildcardNotifyMinutesBefore: v),
  );

  Future<void> setDefaultTab(int v) =>
      _setInt(PrefsKeys.defaultTab, v, (s) => s.copyWith(defaultTab: v));

  Future<void> setFavoriteRankedMapNames(List<String> v) => _setStringList(
    PrefsKeys.favoriteRankedMapNames,
    v,
    (s) => s.copyWith(favoriteRankedMapNames: v),
  );

  Future<void> setFavoritePubsMapNames(List<String> v) => _setStringList(
    PrefsKeys.favoritePubsMapNames,
    v,
    (s) => s.copyWith(favoritePubsMapNames: v),
  );

  Future<void> clear() async {
    await Future.wait([
      _prefs.remove(PrefsKeys.profiles),
      _prefs.remove(PrefsKeys.activeProfileIndex),
      _prefs.remove(PrefsKeys.playerName),
      _prefs.remove(PrefsKeys.playerUid),
      _prefs.remove(PrefsKeys.playerPlatform),
      _prefs.remove(PrefsKeys.notifyPubsMapRotation),
      _prefs.remove(PrefsKeys.notifyRankedMapRotation),
      _prefs.remove(PrefsKeys.notifyMixtapeMapRotation),
      _prefs.remove(PrefsKeys.notifyWildcardMapRotation),
      _prefs.remove(PrefsKeys.rankedNotifyMinutes),
      _prefs.remove(PrefsKeys.pubsNotifyMinutes),
      _prefs.remove(PrefsKeys.mixtapeNotifyMinutes),
      _prefs.remove(PrefsKeys.wildcardNotifyMinutes),
      _prefs.remove(PrefsKeys.favoriteRankedMapNames),
      _prefs.remove(PrefsKeys.favoritePubsMapNames),
      _prefs.remove(PrefsKeys.statsRefreshMinutes),
      _prefs.remove(PrefsKeys.compactLegendCards),
      _prefs.remove(PrefsKeys.defaultTab),
    ]);
    state = state.copyWith(
      profiles: [],
      activeProfileIndex: 0,
      notifyPubsMapRotation: false,
      notifyRankedMapRotation: false,
      notifyMixtapeMapRotation: false,
      notifyWildcardMapRotation: false,
      rankedNotifyMinutesBefore: 0,
      pubsNotifyMinutesBefore: 0,
      mixtapeNotifyMinutesBefore: 0,
      wildcardNotifyMinutesBefore: 0,
      favoriteRankedMapNames: [],
      favoritePubsMapNames: [],
      statsRefreshMinutes: 0,
      compactLegendCards: false,
      defaultTab: 0,
    );
  }
}

/// Global app settings provider. Watch this in UI; call notifier methods
/// (e.g. `ref.read(playerSettingsProvider.notifier).setPlayer(...)`) to persist changes.
final playerSettingsProvider =
    NotifierProvider<PlayerSettingsNotifier, PlayerSettings>(
      PlayerSettingsNotifier.new,
    );
