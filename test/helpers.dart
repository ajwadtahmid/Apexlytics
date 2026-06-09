import 'package:apexlytics/models/player_stats.dart';

/// Builds a minimal [PlayerStats] for use in tests. Override only the fields
/// you care about; everything else gets a sensible default.
PlayerStats buildStats({
  String name = 'TestPlayer',
  String uid = 'uid123',
  int rankScore = 1000,
  String rank = 'Gold',
  String platform = 'PC',
  bool isOnline = false,
  bool isInGame = false,
  List<LegendStat>? legendStats,
}) {
  return PlayerStats(
    name: name,
    uid: uid,
    level: 100,
    rank: rank,
    rankScore: rankScore,
    platform: platform,
    currentLegend: 'Wraith',
    isOnline: isOnline,
    isInGame: isInGame,
    trackers: [],
    legendStats: legendStats ?? [],
  );
}

/// Builds a [LegendTracker] for use in tests.
LegendTracker buildTracker({
  String key = 'kills',
  String? displayName,
  int value = 100,
}) {
  return LegendTracker(
    key: key,
    displayName: displayName ?? key,
    value: value,
  );
}

/// Builds a [LegendStat] for use in tests.
LegendStat buildLegend({
  String name = 'Wraith',
  List<LegendTracker>? trackers,
}) {
  return LegendStat(
    name: name,
    trackers: trackers ?? [buildTracker()],
  );
}
