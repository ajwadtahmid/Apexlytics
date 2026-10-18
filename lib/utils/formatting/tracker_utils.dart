import '../../constants/tracker_constants.dart';
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

/// One cell of a legend card's tracker grid. A null [value] has no reading.
class TrackerCell {
  final String label;
  final int? value;
  const TrackerCell(this.label, this.value);
}

/// The four cells of a legend card's tracker grid, row by row, and how many
/// trackers there was no room for.
class LegendCardTrackers {
  /// Top-left, top-right, bottom-left, bottom-right. A null cell is left blank.
  final List<TrackerCell?> cells;

  /// Trackers the legend has that the cells don't show, for its own page.
  final int hidden;

  const LegendCardTrackers(this.cells, this.hidden);
}

/// Lays [trackers] out as a 2 by 2 grid that is the same shape for every
/// legend. The first row starts with kills and the second with damage, shown as
/// no reading when the legend doesn't have them; the cell beside each takes the
/// next tracker in the legend's own order, or stays blank. A second kills or
/// damage tracker under the same name isn't repeated.
///
/// The career card ([career]) has no Battle Royale kills or damage; its cells
/// are career kills, wins and revives, with the last one blank.
LegendCardTrackers legendCardTrackers(
  List<LegendTracker> trackers, {
  bool career = false,
}) {
  TrackerCell cell(LegendTracker t) => TrackerCell(t.displayName, t.value);

  LegendTracker? named(bool Function(LegendTracker) test) {
    LegendTracker? best;
    for (final t in trackers) {
      if (test(t) && (best == null || t.value > best.value)) best = t;
    }
    return best;
  }

  if (career) {
    LegendTracker? find(String name) => named(
      (t) =>
          t.displayName.toLowerCase() == name ||
          t.key.toLowerCase() == name.replaceAll(' ', '_'),
    );
    final kills = find('career kills');
    final wins = find('career wins');
    final revives = find('career revives');
    return LegendCardTrackers([
      TrackerCell('Career Kills', kills?.value),
      TrackerCell('Career Wins', wins?.value),
      TrackerCell('Career Revives', revives?.value),
      null,
    ], trackers.length - [kills, wins, revives].where((t) => t != null).length);
  }

  final kills = named(
    (t) => t.displayName.toLowerCase() == TrackerKeys.brKills,
  );
  final damage = named(
    (t) => t.displayName.toLowerCase() == TrackerKeys.brDamage,
  );
  final others = [
    for (final t in trackers)
      if (t.displayName.toLowerCase() != TrackerKeys.brKills &&
          t.displayName.toLowerCase() != TrackerKeys.brDamage)
        t,
  ];
  TrackerCell? other(int i) => i < others.length ? cell(others[i]) : null;
  final shownOthers = others.length < 2 ? others.length : 2;
  final shownLead = (kills == null ? 0 : 1) + (damage == null ? 0 : 1);

  return LegendCardTrackers([
    TrackerCell('BR Kills', kills?.value),
    other(0),
    TrackerCell('BR Damage', damage?.value),
    other(1),
  ], trackers.length - shownLead - shownOthers);
}

/// Returns a display-name → value map from deduplicated [trackers].
Map<String, int> trackerValueMap(List<LegendTracker> trackers) => {
  for (final t in deduplicateTrackers(trackers))
    t.displayName.toLowerCase(): t.value,
};
