class PrefsKeys {
  static const profiles = 'player_profiles';
  static const activeProfileIndex = 'active_profile_index';

  // Legacy single-player keys — kept for migration only
  static const playerName = 'player_name';
  static const playerUid = 'player_uid';
  static const playerPlatform = 'player_platform';

  static const statsRefreshMinutes = 'stats_refresh_minutes';
  static const compactLegendCards = 'compact_legend_cards';

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
  static const uidSearchWarningShown = 'uid_search_warning_shown';

  /// Cached `/approved-uids` allowlist (JSON list of UID strings). Read
  /// synchronously on launch so the gated Ranked tab appears without a network
  /// round-trip; refreshed in the background.
  static const approvedUidsCache = 'approved_uids_cache';

  static const legendStats = 'legend_stats';
  static const legendVisitStack = 'legend_visit_stack';
  static const seasonHistory = 'season_history';

  // Legacy global snapshot key — kept for backup compatibility only.
  // Modern code uses 'stat_snapshots_<uid>' instead.
  static const statSnapshots = 'stat_snapshots';

  /// Builds UID-scoped key for snapshots: `stat_snapshots_<uid>` or `stat_snapshots` (legacy).
  /// The global key intentionally lacks the `_` suffix for backwards compatibility
  /// with data accumulated before UID support was added.
  static String snapshotKeyFor(String? uid) =>
      uid?.isNotEmpty == true ? 'stat_snapshots_$uid' : statSnapshots;

  /// Builds UID-scoped key for legend stats: `legend_stats_<uid>` or `legend_stats` (legacy).
  static String legendStatsKeyFor(String? uid) =>
      uid?.isNotEmpty == true ? 'legend_stats_$uid' : 'legend_stats';

  /// Builds UID-scoped key for the ranked goal (a [kRankLadder] index the player
  /// is climbing toward). Absent = no goal set; the card falls back to tracking
  /// the next division automatically.
  static String rankGoalKeyFor(String uid) => 'rank_goal_$uid';
}
