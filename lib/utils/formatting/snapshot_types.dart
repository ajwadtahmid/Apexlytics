import 'package:flutter/foundation.dart' show listEquals;
import '../../models/season_meta.dart';

/// RP-drop size read as a reset on snapshots with no split id. See
/// [lastResetIndex].
const int kRpResetDropThreshold = 1000;

/// Window after a declared split start within which a legacy RP drop is read
/// as that split's reset. See [lastResetIndex].
const Duration kResetObservationWindow = Duration(hours: 48);

/// Drops 0 readings when the snapshot stream shows the player has scored
/// before — `/bridge` intermittently reports `rankScore: 0` around a rollover.
List<StatSnapshot> trustedSnapshots(List<StatSnapshot> snaps) {
  if (!snaps.any((s) => s.rp > 0)) return snaps;
  return snaps.where((s) => s.rp > 0).toList();
}

class StatSnapshot {
  final DateTime timestamp;
  final int rp;

  /// The ranked split (`SeasonMeta.id`) this RP was read in, e.g.
  /// `br_ranked_s30_s1`. Null for snapshots written before the field existed.
  final String? seasonId;

  const StatSnapshot({
    required this.timestamp,
    required this.rp,
    this.seasonId,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp.millisecondsSinceEpoch,
    'rp': rp,
    if (seasonId != null) 'sid': seasonId,
  };

  factory StatSnapshot.fromJson(Map<String, dynamic> json) => StatSnapshot(
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    rp: json['rp'] as int,
    seasonId: json['sid'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatSnapshot &&
          timestamp == other.timestamp &&
          rp == other.rp &&
          seasonId == other.seasonId;

  @override
  int get hashCode => Object.hash(timestamp, rp, seasonId);
}

/// Index of the snapshot immediately *following* the most recent reset in
/// [snaps] (oldest-first, already through [trustedSnapshots]), or null.
///
/// A split id change is the authoritative signal; two snapshots known to share a
/// split are never a reset however far RP fell. Legacy snapshots have no id, so
/// they fall back to [kRpResetDropThreshold] — accepted only within
/// [kResetObservationWindow] of [splitStart], or unconditionally when no
/// [splitStart] is known (the season-less 24h delta).
int? lastResetIndex(List<StatSnapshot> snaps, {DateTime? splitStart}) {
  for (var i = snaps.length - 1; i > 0; i--) {
    final prevId = snaps[i - 1].seasonId;
    final curId = snaps[i].seasonId;
    if (prevId != null && curId != null) {
      if (prevId != curId) return i;
      continue;
    }
    if (snaps[i].rp - snaps[i - 1].rp > -kRpResetDropThreshold) continue;
    if (splitStart == null) return i;
    final at = snaps[i].timestamp;
    if (!at.isBefore(splitStart) &&
        at.isBefore(splitStart.add(kResetObservationWindow))) {
      return i;
    }
  }
  return null;
}

/// Returns the RP gained over the last 24 hours.
/// Uses the most recent snapshot from 24+ hours ago as baseline; falls back
/// to the first available snapshot if all data is within the last 24 hours.
int? computeDelta(List<StatSnapshot> rawSnaps, int currentRp) {
  final snaps = trustedSnapshots(rawSnaps);
  if (snaps.isEmpty) return null;
  final now = DateTime.now();
  final dayAgo = now.subtract(const Duration(days: 1));

  // Find the most recent snapshot from 24+ hours ago.
  StatSnapshot? baseline;
  for (final s in snaps.reversed) {
    if (s.timestamp.isBefore(dayAgo)) {
      baseline = s;
      break;
    }
  }

  // Fall back to the first (oldest) snapshot if all data is within 24h.
  baseline ??= snaps.first;

  // A reset since the baseline would make the difference *be* the reset.
  final resetIdx = lastResetIndex(snaps);
  if (resetIdx != null &&
      snaps[resetIdx].timestamp.isAfter(baseline.timestamp)) {
    baseline = snaps[resetIdx];
  }
  return currentRp - baseline.rp;
}

/// Aggregated snapshot metadata for a ranked season.
class SeasonSnapshot {
  final SeasonMeta season;
  final List<StatSnapshot> snapshots;

  const SeasonSnapshot({required this.season, required this.snapshots});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeasonSnapshot &&
          season == other.season &&
          listEquals(snapshots, other.snapshots);

  @override
  int get hashCode => Object.hash(season, Object.hashAll(snapshots));
}
