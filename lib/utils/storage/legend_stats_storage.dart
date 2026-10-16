import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/prefs_keys.dart';
import '../../models/player_stats.dart';
import '../app_logger.dart';

List<LegendStat> _parseLegendStats(String? raw) {
  try {
    final decoded = jsonDecode(raw ?? '[]');
    if (decoded is! List) {
      log.w('Stored legend stats blob is not a list — treating as empty');
      return [];
    }
    // Entry by entry: [mergeLegendStats] writes back whatever this returns, so
    // one unreadable legend must not take every other legend's accumulated
    // trackers with it.
    final legends = <LegendStat>[];
    var skipped = 0;
    for (final entry in decoded.whereType<Map<String, dynamic>>()) {
      try {
        legends.add(LegendStat.fromJson(entry));
      } catch (_) {
        skipped++;
      }
    }
    if (skipped > 0) log.w('Skipped $skipped unreadable stored legend entries');
    return legends;
  } catch (e) {
    // Well-formed-but-wrong-shape JSON throws TypeError, not
    // FormatException — see rp_snapshot_storage._parseSnapshots.
    log.w('Legend stats JSON parse failed — returning empty list', error: e);
    return [];
  }
}

List<LegendStat> loadLegendStats(SharedPreferences prefs, {String? uid}) {
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
    final newTimestamp =
        (existing == null || _legendStatsChanged(existing, merged))
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
