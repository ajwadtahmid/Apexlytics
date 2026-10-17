class PrefsKeys {
  static const profiles = 'player_profiles';
  static const activeProfileIndex = 'active_profile_index';

  // Device-local owner flag (the token itself lives in secure storage). Kept
  // out of backups on purpose — see backup_service's allowlist.
  static const ownerUnlocked = 'owner_unlocked';

  // Legacy single-player keys — kept for migration only
  static const playerName = 'player_name';
  static const playerUid = 'player_uid';
  static const playerPlatform = 'player_platform';

  static const statsRefreshMinutes = 'stats_refresh_minutes';
  static const keepScreenOn = 'keep_screen_on';

  // Legacy global timing key — kept only for one-time migration to per-mode keys.
  static const mapNotifyMinutes = 'map_notify_minutes';

  static const notifyPubsMapRotation = 'notify_pubs_map_rotation';
  static const notifyRankedMapRotation = 'notify_ranked_map_rotation';
  static const notifyMixtapeMapRotation = 'notify_mixtape_map_rotation';
  static const notifyWildcardMapRotation = 'notify_wildcard_map_rotation';

  static const rankedNotifyMinutes = 'ranked_notify_minutes';
  static const pubsNotifyMinutes = 'pubs_notify_minutes';
  static const mixtapeNotifyMinutes = 'mixtape_notify_minutes';
  static const wildcardNotifyMinutes = 'wildcard_notify_minutes';

  static const favoriteRankedMapNames = 'favorite_ranked_map_names';
  static const favoritePubsMapNames = 'favorite_pubs_map_names';

  static const defaultTab = 'default_tab';
  static const searchFavorites = 'search_favorites';

  /// The last few players looked up, newest first. Device-only: not backed up.
  static const recentSearches = 'recent_searches';
  static const uidSearchWarningShown = 'uid_search_warning_shown';

  /// How many sessions the Performance Trends page looks at (0 for all of
  /// them). Device-only: not backed up.
  static const trendSessionsShown = 'trend_sessions_shown';
  static const rankedInfoCoachMarkShown = 'ranked_info_coach_mark_shown';

  /// Highest [kOnboardingVersion] the user has seen. Absent/lower than the
  /// current version means the orientation tour is shown once on next launch.
  static const onboardingVersion = 'onboarding_version';

  static const legendStats = 'legend_stats';

  /// Legacy global legend stack; seeds the first profile that loads, then is removed.
  static const legendVisitStack = 'legend_visit_stack';

  /// Prefix of the per-UID legend stack (for backup matching).
  static const legendVisitStackPrefix = 'legend_visit_stack_';

  /// Per-UID legend stack key; the legacy global key without a UID.
  static String legendVisitStackKeyFor(String? uid) => uid?.isNotEmpty == true
      ? '$legendVisitStackPrefix$uid'
      : legendVisitStack;

  static const seasonHistory = 'season_history';

  // Legacy global snapshot key — kept for backup compatibility only.
  // Modern code uses 'stat_snapshots_<uid>' instead.
  static const statSnapshots = 'stat_snapshots';

  /// Prefix of the UID-scoped snapshot keys, `stat_snapshots_<uid>`.
  static const snapshotKeyPrefix = '${statSnapshots}_';

  /// Builds UID-scoped key for snapshots: `stat_snapshots_<uid>` or `stat_snapshots` (legacy).
  /// The global key intentionally lacks the `_` suffix for backwards compatibility
  /// with data accumulated before UID support was added.
  static String snapshotKeyFor(String? uid) =>
      uid?.isNotEmpty == true ? '$snapshotKeyPrefix$uid' : statSnapshots;

  /// Prefix of the UID-scoped legend stats keys, `legend_stats_<uid>`.
  static const legendStatsKeyPrefix = '${legendStats}_';

  /// Builds UID-scoped key for legend stats: `legend_stats_<uid>` or `legend_stats` (legacy).
  static String legendStatsKeyFor(String? uid) =>
      uid?.isNotEmpty == true ? '$legendStatsKeyPrefix$uid' : legendStats;

  /// The cyclic map rotation order, shared by the foreground provider and the
  /// background fetch isolate.
  static const seasonalMapsCache = 'seasonal_maps_cache';

  /// Outcome of the most recent background fetch; device-local, not backed up.
  static const bgFetchLastResult = 'bg_fetch_last_result';

  /// Prefix for the UID-scoped ranked goal. Named so backup and clear can
  /// match it by prefix - a bare literal here is how the goal escaped both.
  static const rankGoalPrefix = 'rank_goal_';

  /// Builds UID-scoped key for the ranked goal (a [kRankLadder] index the player
  /// is climbing toward). Absent = no goal set; the card falls back to tracking
  /// the next division automatically.
  static String rankGoalKeyFor(String uid) => '$rankGoalPrefix$uid';

  /// The goal for one split of [uid]: `rank_goal_<uid>@<splitId>`. A goal
  /// belongs to the split it was set in. The plain [rankGoalKeyFor] key is what
  /// older versions wrote for every split at once.
  static String rankGoalKeyForSplit(String uid, String splitId) =>
      '$rankGoalPrefix$uid@$splitId';

  /// Earliest time (epoch ms) the app may ask `/games` for [uid] again.
  static String gamesNextSync(String uid) => 'games_next_sync_$uid';

  /// The last `RankedSyncOutcome` name recorded for [uid].
  static String gamesLastOutcome(String uid) => 'games_last_outcome_$uid';
}
