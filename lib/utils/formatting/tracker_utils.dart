import '../../models/player_stats.dart';

/// Deduplicates [trackers] by key (the stable API identifier), keeping the highest value for each.
List<LegendTracker> deduplicateTrackers(List<LegendTracker> trackers) {
  final deduped = <String, LegendTracker>{};
  for (final t in trackers) {
    if (!deduped.containsKey(t.key) || t.value > deduped[t.key]!.value) {
      deduped[t.key] = t;
    }
  }
  return deduped.values.toList();
}

/// Returns a display-name → value map from deduplicated [trackers].
Map<String, int> trackerValueMap(List<LegendTracker> trackers) => {
  for (final t in deduplicateTrackers(trackers))
    t.displayName.toLowerCase(): t.value,
};
