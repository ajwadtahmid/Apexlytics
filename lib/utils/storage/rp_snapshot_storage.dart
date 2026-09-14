import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/prefs_keys.dart';
import '../../models/player_stats.dart';
import '../../models/season_meta.dart';
import '../app_logger.dart';
import 'ranked_history_store.dart';
import 'season_storage.dart';
import '../formatting/season_utils.dart';
import '../formatting/snapshot_types.dart';

/// Legacy prefix for RP snapshot keys, `stat_snapshots_<uid>`.
///
/// Snapshots now live in the `stat_snapshots` table (schema v8). This is kept
/// for two reasons: [migrateSnapshotsFromPrefs] drains it, and v2 backup files
/// still carry the prefs form, so `backup_service` must keep accepting it.
const String snapshotKeyPrefix = 'stat_snapshots_';

/// Per-UID snapshots held in memory, oldest first - the table is the durable
/// copy, but the RP graph renders on frame 1 and SQLite is async, so reads
/// are served from here. [primeSnapshots] fills it, [loadSnapshotsSync] reads
/// it, [appendSnapshot] keeps both in step. Keyed like [PrefsKeys.snapshotKeyFor].
final Map<String, List<StatSnapshot>> _cache = {};

/// Drops every cached entry. For "Clear all data" and for test isolation -
/// without it a cleared database would still read back through this cache.
void resetSnapshotCache() => _cache.clear();

@visibleForTesting
bool isSnapshotCachePrimed(String? uid) =>
    _cache.containsKey(PrefsKeys.snapshotKeyFor(uid));

/// Parses a legacy prefs blob into snapshots, or an empty list when it can't
/// be read at all.
///
/// Deliberately broad: `jsonDecode` succeeding on well-formed-but-wrong-shape
/// JSON (e.g. `{"a":1}`) throws a [TypeError] on the `as List` cast, not a
/// [FormatException] - narrower error handling here let that case escape
/// [migrateSnapshotsFromPrefs] and abort the drain of every later key.
List<StatSnapshot> _parseSnapshots(String? raw) {
  try {
    final decoded = jsonDecode(raw ?? '[]');
    if (decoded is! List) {
      log.w('RP snapshot blob is not a list — treating as unparseable');
      return const [];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(StatSnapshot.fromJson)
        .toList();
  } catch (e) {
    log.w('RP snapshot JSON parse failed — returning empty list', error: e);
    return const [];
  }
}

/// Moves any snapshots still in SharedPreferences into [store].
///
/// Driven by the presence of legacy keys, not a "migrated" flag - a flag set
/// on first launch would wrongly suppress the drain when an older backup
/// (which carries snapshots as prefs, not table rows) is imported later.
/// Each key is removed only after its rows commit, and the insert is
/// idempotent, so an interrupted or repeated run is safe.
///
/// A key whose blob fails to parse is left in place rather than removed: an
/// empty result from [_parseSnapshots] is ambiguous between "nothing to
/// migrate" and "couldn't read this" and only the former is safe to discard
/// - deleting an unreadable blob would destroy the only copy of that
/// player's RP history with no recovery path.
Future<void> migrateSnapshotsFromPrefs(
  SharedPreferences prefs,
  RankedHistoryStore store,
) async {
  final legacyKeys = prefs
      .getKeys()
      .where(
        (k) => k.startsWith(snapshotKeyPrefix) || k == PrefsKeys.statSnapshots,
      )
      .toList();
  if (legacyKeys.isEmpty) return;

  final drained = <String>[];
  for (final key in legacyKeys) {
    final raw = prefs.getString(key);
    final snaps = _parseSnapshots(raw);
    if (snaps.isEmpty) {
      // A genuinely empty or absent blob has nothing to lose by removing;
      // anything else means the blob held content we couldn't read.
      if (raw == null || raw.isEmpty || raw == '[]') drained.add(key);
      continue;
    }
    // The UID-less legacy key has no owner; it predates multi-profile support
    // and its data belongs to whoever was linked at the time. Keeping it under
    // the empty-uid bucket matches how snapshotKeyFor(null) already reads it.
    final uid = key == PrefsKeys.statSnapshots
        ? ''
        : key.substring(snapshotKeyPrefix.length);
    await store.appendSnapshotsFor(uid, snaps);
    log.i('Migrated ${snaps.length} RP snapshots to SQLite');
    drained.add(key); // only after the rows commit
  }

  for (final key in drained) {
    await prefs.remove(key);
  }
  // Anything already cached was read before the drain and is now incomplete.
  resetSnapshotCache();
}

/// Loads [uid]'s snapshots from [store] into the cache. Call before the first
/// synchronous read for that UID - on app start for the active profile, and on
/// profile switch.
Future<List<StatSnapshot>> primeSnapshots(
  RankedHistoryStore store,
  String? uid,
) async {
  final snaps = await store.snapshotsFor(uid ?? '');
  _cache[PrefsKeys.snapshotKeyFor(uid)] = snaps;
  return snaps;
}

/// Synchronous read, served from the cache filled by [primeSnapshots].
/// Returns empty for a UID that has not been primed yet - the graph fills in
/// on the frame after priming completes rather than blocking the first one.
List<StatSnapshot> loadSnapshotsSync({String? uid}) =>
    _cache[PrefsKeys.snapshotKeyFor(uid)] ?? const [];

/// Appends a reading for [uid], if it is one worth keeping.
///
/// Returns the updated list. Skips (returning the current list unchanged) when
/// the reading is an untrustworthy zero or a duplicate of the last one.
Future<List<StatSnapshot>> appendSnapshot(
  PlayerStats stats,
  RankedHistoryStore store, {
  String? uid,
  bool deduplicateRp = true,
}) async {
  final key = PrefsKeys.snapshotKeyFor(uid);
  // A UID that was never primed would otherwise dedup against an empty list
  // and re-append a reading already on disk.
  final snapshots = _cache.containsKey(key)
      ? _cache[key]!
      : await primeSnapshots(store, uid);

  final seasonId = stats.rankedSeason?.id;

  // Keeps a mid-rollover `rankScore: 0` from planting a fake reset floor. See
  // [trustedSnapshots], which does the same for entries already on disk.
  if (stats.rankScore == 0 && snapshots.any((s) => s.rp > 0)) return snapshots;

  // Dedup covers the split too — that entry marks where the reset fell, so it
  // must survive even when RP lands on the same number.
  if (snapshots.isNotEmpty &&
      deduplicateRp &&
      snapshots.last.rp == stats.rankScore &&
      snapshots.last.seasonId == seasonId) {
    return snapshots;
  }

  // `(uid, ts_ms)` is the primary key, so two appends in the same millisecond
  // would replace each other instead of both landing - nudge forward to keep
  // the series strictly increasing. Compared in whole milliseconds, not with
  // DateTime.isAfter: DateTime's microsecond precision would still collide on
  // the truncated column.
  final lastMs = snapshots.isEmpty
      ? null
      : snapshots.last.timestamp.millisecondsSinceEpoch;
  var nowMs = DateTime.now().millisecondsSinceEpoch;
  if (lastMs != null && nowMs <= lastMs) nowMs = lastMs + 1;

  final snapshot = StatSnapshot(
    timestamp: DateTime.fromMillisecondsSinceEpoch(nowMs),
    rp: stats.rankScore,
    seasonId: seasonId,
  );
  await store.appendSnapshotFor(uid ?? '', snapshot);
  // One row appended, one list element appended - no full re-encode of the
  // series, which is what made the old prefs blob O(n) on every poll tick.
  final updated = [...snapshots, snapshot];
  _cache[key] = updated;
  return updated;
}

/// Appends a snapshot and returns the updated list for `stats.uid`.
Future<List<StatSnapshot>> appendAndLoadSnapshots(
  PlayerStats stats,
  RankedHistoryStore store, {
  bool deduplicateRp = true,
}) =>
    appendSnapshot(stats, store, uid: stats.uid, deduplicateRp: deduplicateRp);

/// Loads snapshots, seasons, and computes RP delta for a player in one call.
/// Used by state initialization in stats views to populate all snapshot-related
/// data. Reads the primed cache, so it stays synchronous.
({List<StatSnapshot> snapshots, Map<String, SeasonMeta> allSeasons, int? delta})
initSnapshotsData(
  SharedPreferences prefs,
  String uid,
  SeasonMeta? season,
  int currentRp,
) {
  final snaps = loadSnapshotsSync(uid: uid);
  final seasons = loadAllSeasonsSync(prefs);
  final delta = computeWeekDelta(snaps, season, currentRp);
  return (snapshots: snaps, allSeasons: seasons, delta: delta);
}
