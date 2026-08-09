import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/prefs_keys.dart';
import '../../models/player_stats.dart';
import '../../models/season_meta.dart';
import '../app_logger.dart';
import 'season_storage.dart';
import '../formatting/season_utils.dart';
import '../formatting/snapshot_types.dart';

/// Prefix for RP snapshot keys. Keys are stored as `stat_snapshots_<uid>`.
/// Included in backups to preserve historical RP data across app reinstalls.
const String snapshotKeyPrefix = 'stat_snapshots_';

// No cap — snapshots grow only when RP changes (dedup), so the total is
// bounded by the number of matches played across the life of the app.

List<StatSnapshot> _parseSnapshots(String? raw) {
  try {
    final list = jsonDecode(raw ?? '[]') as List;
    return list
        .whereType<Map<String, dynamic>>()
        .map(StatSnapshot.fromJson)
        .toList();
  } on FormatException catch (e) {
    log.w('RP snapshot JSON parse failed — returning empty list', error: e);
    return [];
  }
}

/// Synchronous read — SharedPreferences.getString is in-memory after app init,
/// so this never blocks. Use this to populate the graph on the first frame.
List<StatSnapshot> loadSnapshotsSync(SharedPreferences prefs, {String? uid}) =>
    _parseSnapshots(prefs.getString(PrefsKeys.snapshotKeyFor(uid)));

Future<void> appendSnapshot(
  PlayerStats stats,
  SharedPreferences prefs, {
  String? uid,
  bool deduplicateRp = true,
}) async {
  final snapshots = _parseSnapshots(prefs.getString(PrefsKeys.snapshotKeyFor(uid)));
  final now = DateTime.now();
  final seasonId = stats.rankedSeason?.id;

  // Keeps a mid-rollover `rankScore: 0` from planting a fake reset floor. See
  // [trustedSnapshots], which does the same for entries already on disk.
  if (stats.rankScore == 0 && snapshots.any((s) => s.rp > 0)) return;

  // Dedup covers the split too — that entry marks where the reset fell, so it
  // must survive even when RP lands on the same number.
  if (snapshots.isNotEmpty &&
      deduplicateRp &&
      snapshots.last.rp == stats.rankScore &&
      snapshots.last.seasonId == seasonId) {
    return;
  }

  snapshots.add(
    StatSnapshot(timestamp: now, rp: stats.rankScore, seasonId: seasonId),
  );

  await prefs.setString(
    PrefsKeys.snapshotKeyFor(uid),
    jsonEncode(snapshots.map((s) => s.toJson()).toList()),
  );
}

/// Appends a snapshot and returns the updated snapshot list.
Future<List<StatSnapshot>> appendAndLoadSnapshots(
  PlayerStats stats,
  SharedPreferences prefs, {
  bool deduplicateRp = true,
}) async {
  await appendSnapshot(stats, prefs, uid: stats.uid, deduplicateRp: deduplicateRp);
  return loadSnapshotsSync(prefs, uid: stats.uid);
}

/// Loads snapshots, seasons, and computes RP delta for a player in one call.
/// Used by state initialization in stats views to populate all snapshot-related data.
({List<StatSnapshot> snapshots, Map<String, SeasonMeta> allSeasons, int? delta})
    initSnapshotsData(
  SharedPreferences prefs,
  String uid,
  SeasonMeta? season,
  int currentRp,
) {
  final snaps = loadSnapshotsSync(prefs, uid: uid);
  final seasons = loadAllSeasonsSync(prefs);
  final delta = computeWeekDelta(snaps, season, currentRp);
  return (snapshots: snaps, allSeasons: seasons, delta: delta);
}
