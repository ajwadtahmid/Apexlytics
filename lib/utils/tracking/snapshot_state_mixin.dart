import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/player_stats.dart';
import '../../models/season_meta.dart';
import '../storage/rp_snapshot_storage.dart';
import '../storage/season_storage.dart';
import '../formatting/season_utils.dart';
import '../formatting/snapshot_types.dart';

/// Manages the snapshot/season state shared by every stats view.
///
/// Mix into any [State] subclass that shows an RP history graph:
/// - [snapshots], [allSeasons], [rpDelta] replace the three identically-named
///   private fields that each view previously declared independently.
/// - [initSnapshotFields] is the synchronous frame-1 init (call in initState
///   and on UID change).
/// - [appendSnapshotState] handles the async write → reload → setState cycle
///   for views that only need snapshot data (no legend-stack merge).
mixin SnapshotStateMixin {
  List<StatSnapshot> snapshots = [];
  Map<String, SeasonMeta> allSeasons = {};
  int? rpDelta;

  // Abstract declarations satisfied by State (avoids a 'on State<T>' constraint,
  // which would prevent use with both State<_StatsBody> and ConsumerState<T>).
  void setState(VoidCallback fn);
  bool get mounted;

  /// Synchronously pre-populates fields from the on-disk cache so the graph
  /// renders on frame 1 without a layout shift.
  void initSnapshotFields(
    SharedPreferences prefs,
    String uid,
    SeasonMeta? rankedSeason,
    int rankScore,
  ) {
    final data = initSnapshotsData(prefs, uid, rankedSeason, rankScore);
    snapshots = data.snapshots;
    allSeasons = data.allSeasons;
    rpDelta = data.delta;
  }

  /// Upserts the current season, appends the new data point, then refreshes
  /// [snapshots], [allSeasons], and [rpDelta] via [setState].
  ///
  /// Used by views that only need snapshot state (not legend-stack merging).
  /// Views that need to update additional fields in the same setState call
  /// should call [appendSnapshot] + [loadSnapshotsSync] directly and fold
  /// the snapshot fields into their own setState block.
  ///
  /// Returns whether a new/changed season was learned, so a
  /// [ConsumerState] caller can invalidate anything caching the season
  /// list elsewhere (e.g. the ranked breakdown's split picker).
  Future<bool> appendSnapshotState(
    SharedPreferences prefs,
    PlayerStats stats,
  ) async {
    if (!mounted) return false;
    final season = stats.rankedSeason;
    final seasonChanged =
        season != null ? await upsertSeason(season, prefs) : false;
    if (!mounted) return seasonChanged;
    await appendSnapshot(stats, prefs, uid: stats.uid);
    final snaps = loadSnapshotsSync(prefs, uid: stats.uid);
    if (!mounted) return seasonChanged;
    setState(() {
      snapshots = snaps;
      allSeasons = loadAllSeasonsSync(prefs);
      rpDelta = computeWeekDelta(snaps, stats.rankedSeason, stats.rankScore);
    });
    return seasonChanged;
  }
}
