import '../../constants/weapon_constants.dart';
import '../../models/player_stats.dart';

final _reAlphanumeric = RegExp(r'[a-z0-9]');

/// Returns the weapon whose name leads the tracker display name, or null if
/// the tracker is not weapon-specific. Tracker names follow "[WeaponName]
/// [StatType]" (e.g. "R-301 Kills"). The boundary check prevents "career"
/// matching "car" (C.A.R. alt-name) since 'e' fails the alphanumeric test.
Weapon? findWeaponFromTracker(String displayName) {
  final lower = displayName.toLowerCase();
  Weapon? highestMatch;
  int bestLen = 0;

  for (final w in kAllWeapons) {
    for (final candidate in [w.name, w.fullName, ...w.altNames]) {
      final cLower = candidate.toLowerCase();
      if (cLower.length <= bestLen) continue;
      if (!lower.startsWith(cLower)) continue;
      final nextIdx = cLower.length;
      final atBoundary =
          nextIdx >= lower.length || !_reAlphanumeric.hasMatch(lower[nextIdx]);
      if (!atBoundary) continue;
      // Longest match ensures "R-301 Carbine" is preferred over "R-99" when
      // matching tracker names like "R-301 Carbine Kills".
      highestMatch = w;
      bestLen = cLower.length;
    }
  }

  return highestMatch;
}

/// Scans all legend trackers and maps each to a known weapon by display name.
/// Returns weapon → {statName → bestValue} for any matched trackers.
Map<Weapon, Map<String, int>> extractWeaponStats(List<LegendStat> legendStats) {
  final result = <Weapon, Map<String, int>>{};

  for (final legend in legendStats) {
    for (final tracker in legend.trackers) {
      final weapon = findWeaponFromTracker(tracker.displayName);
      if (weapon == null) continue;
      final bucket = result.putIfAbsent(weapon, () => {});
      final key = tracker.displayName.toLowerCase();
      final existing = bucket[key] ?? 0;
      if (tracker.value > existing) bucket[key] = tracker.value;
    }
  }

  return result;
}
