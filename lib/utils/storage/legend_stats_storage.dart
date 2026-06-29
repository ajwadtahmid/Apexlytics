import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/prefs_keys.dart';
import '../../models/player_stats.dart';
import '../app_logger.dart';

/// Prefix for legend stats keys. Keys are stored as `legendStats_<uid>`.
/// Included in backups to preserve legend statistics across app reinstalls.
const String legendStatsKeyPrefix = '${PrefsKeys.legendStats}_';


List<LegendStat> _parseLegendStats(String? raw) {
  try {
    final list = jsonDecode(raw ?? '[]') as List;
    return list
        .whereType<Map<String, dynamic>>()
        .map(LegendStat.fromJson)
        .toList();
  } on FormatException catch (e) {
    log.w('Legend stats JSON parse failed — returning empty list', error: e);
    return [];
  }
}

List<LegendStat> loadLegendStats(
  SharedPreferences prefs, {
  String? uid,
}) {
  return _parseLegendStats(prefs.getString(PrefsKeys.legendStatsKeyFor(uid)));
}

// Merges incoming legend data into stored data keyed by [uid]:
// - existing legend + existing tracker → update value
// - existing legend + new tracker → append tracker
// - new legend → add it
// Only updates lastUpdated if tracker data actually changed.
Future<List<LegendStat>> mergeLegendStats(
  List<LegendStat> incoming,
  SharedPreferences prefs, {
  String? uid,
}) async {
  final key = PrefsKeys.legendStatsKeyFor(uid);
  final stored = _parseLegendStats(prefs.getString(key));

  if (incoming.isEmpty) return stored;


  final now = DateTime.now();
  final map = <String, LegendStat>{
    for (final legendStat in stored) legendStat.name: legendStat,
  };
  for (final legend in incoming) {
    final existing = map[legend.name];
    final merged = existing != null ? existing.merge(legend) : legend;

    // Only bump lastUpdated when this is a new legend or tracker values changed.
    final newTimestamp = (existing == null || _legendStatsChanged(existing, merged))
        ? now
        : existing.lastUpdated;

    map[legend.name] = LegendStat(
      name: merged.name,
      trackers: merged.trackers,
      lastUpdated: newTimestamp,
    );
  }

  final result = map.values.toList();

  await prefs.setString(
    key,
    jsonEncode(result.map((legendStat) => legendStat.toJson()).toList()),
  );
  return result;
}

// Returns true if tracker values differ between two legend snapshots.
bool _legendStatsChanged(LegendStat previous, LegendStat current) {
  if (previous.trackers.length != current.trackers.length) return true;

  final previousValueByKey = <String, int>{
    for (final t in previous.trackers) t.key: t.value,
  };

  for (final t in current.trackers) {
    if (previousValueByKey[t.key] != t.value) return true;
  }

  return false;
}
