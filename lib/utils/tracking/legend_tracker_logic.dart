/// Legend tracker utilities for extracting and filtering performance metrics.
/// Trackers are achievement records (kills, wins, damage) with numeric values;
/// API responses may contain duplicate entries, so these utilities find and
/// rank them by value to prevent ties.
library;

import '../../models/player_stats.dart';

/// Scans [trackers] for entries matching [test], returning the one with the
/// highest value, or null if none match. Highest-value wins because the API
/// can return duplicate tracker keys — taking the highest is a safe tiebreak.
LegendTracker? findTracker(
  List<LegendTracker> trackers,
  bool Function(LegendTracker) test,
) {
  LegendTracker? highestMatch;
  for (final t in trackers) {
    if (test(t)) {
      if (highestMatch == null || t.value > highestMatch.value) {
        highestMatch = t;
      }
    }
  }
  return highestMatch;
}

const kTopWeaponCategories = 3;

/// Returns up to [kTopWeaponCategories] weapon-category kill trackers, sorted by value descending.
List<LegendTracker> findTopWeaponCategories(List<LegendTracker> trackers) {
  const keywords = [
    'ar',
    'smg',
    'shotgun',
    'lmg',
    'sniper',
    'marksman',
    'pistol',
  ];
  final matches = <LegendTracker>[];
  for (final t in trackers) {
    final lower = t.displayName.toLowerCase();
    if (!lower.contains('kills')) continue;
    final isWeaponCat = keywords.any((k) => lower.contains(k));
    if (isWeaponCat) matches.add(t);
  }
  matches.sort((a, b) => b.value.compareTo(a.value));
  return matches.take(kTopWeaponCategories).toList();
}
