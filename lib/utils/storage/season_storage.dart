import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/prefs_keys.dart';
import '../../models/season_meta.dart';
import '../app_logger.dart';
import '../formatting/season_utils.dart' show kMaxWeeksPerSplit;

Map<String, SeasonMeta> _parseSeasons(String? raw) {
  if (raw == null) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      log.w('Stored season history is not a list — treating as empty');
      return {};
    }
    final result = <String, SeasonMeta>{};
    for (final item in decoded.whereType<Map<String, dynamic>>()) {
      final meta = SeasonMeta.fromJson(item);
      // A placeholder id stored before [upsertSeason] started refusing them
      // is dropped here too, so it stops classifying matches.
      if (meta == null || !SeasonMeta.isSplitId(meta.id)) continue;
      result[meta.id] = meta;
    }
    return result;
  } catch (e) {
    // Well-formed-but-wrong-shape JSON throws TypeError, not
    // FormatException — see rp_snapshot_storage._parseSnapshots.
    log.w('Season history JSON parse failed — returning empty', error: e);
    return {};
  }
}

/// Whether [s] spans a believable split: it ends after it starts, and within
/// the [kMaxWeeksPerSplit] cap [computeWeeks] already applies. A restored window
/// outside that is corrupt or hostile, and — since a match's split is a one-way
/// upgrade — would misfile every unclassified match it happened to cover for good.
bool _isPlausibleWindow(SeasonMeta s) =>
    s.end.isAfter(s.start) &&
    s.end.difference(s.start) <= const Duration(days: 7 * kMaxWeeksPerSplit);

/// The `season_history` blob to store when restoring [backupRaw] onto a device
/// that already holds [deviceRaw]: the backup's valid, plausible windows merged
/// with the device's, the device winning for a split both know (its window came
/// from the live API). A backup with none usable leaves the device's seasons.
String mergeRestoredSeasonHistory({
  required String backupRaw,
  String? deviceRaw,
}) {
  final merged = <String, SeasonMeta>{
    for (final e in _parseSeasons(backupRaw).entries)
      if (_isPlausibleWindow(e.value)) e.key: e.value,
    ..._parseSeasons(deviceRaw),
  };
  return jsonEncode(merged.values.map((s) => s.toJson()).toList());
}

/// Returns all stored seasons, newest first.
Map<String, SeasonMeta> loadAllSeasonsSync(SharedPreferences prefs) =>
    _parseSeasons(prefs.getString(PrefsKeys.seasonHistory));

/// Adds or updates [season] in storage. No-op if start/end are unchanged.
/// Returns whether it actually wrote a new/changed entry, so callers can
/// invalidate anything caching the season list (e.g. the ranked seasons
/// provider).
///
/// A placeholder season (see [SeasonMeta.isSplitId]) is never stored: its
/// window would compete with the real split's when matches are classified.
Future<bool> upsertSeason(SeasonMeta season, SharedPreferences prefs) async {
  if (!SeasonMeta.isSplitId(season.id)) return false;
  final existing = loadAllSeasonsSync(prefs);
  final prev = existing[season.id];
  if (prev != null && prev.start == season.start && prev.end == season.end) {
    return false;
  }
  existing[season.id] = season;
  await prefs.setString(
    PrefsKeys.seasonHistory,
    jsonEncode(existing.values.map((s) => s.toJson()).toList()),
  );
  return true;
}
