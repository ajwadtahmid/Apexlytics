import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/prefs_keys.dart';
import '../../models/player_stats.dart';
import '../../models/season_meta.dart';
import '../app_logger.dart';
import 'ranked_history_store.dart';
import 'season_storage.dart';
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
///
/// Bounded to [_maxCachedUids] entries, least recently used first; an evicted entry is
/// re-read from the table on demand ([_appendSnapshotLocked] primes on a miss).
final Map<String, List<StatSnapshot>> _cache = {};
const int _maxCachedUids = 25;

/// Stores [snaps] under [key] as the most recently used entry.
void _remember(String key, List<StatSnapshot> snaps) {
  _cache.remove(key);
  _cache[key] = snaps;
  while (_cache.length > _maxCachedUids) {
    _cache.remove(_cache.keys.first);
  }
}

/// Notifies after every [resetSnapshotCache], so a view holding its own copy
/// of the snapshot list (the RP graph) knows to re-read after a backup
/// import or a clear, instead of showing the old list until RP next moves.
final snapshotCacheResets = _SnapshotCacheResets();

class _SnapshotCacheResets extends ChangeNotifier {
  void _notify() => notifyListeners();
}

/// Drops every cached entry. For "Clear all data" and for test isolation -
/// without it a cleared database would still read back through this cache.
void resetSnapshotCache() {
  _cache.clear();
  snapshotCacheResets._notify();
}

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
  _remember(PrefsKeys.snapshotKeyFor(uid), snaps);
  return snaps;
}

/// Synchronous read, served from the cache filled by [primeSnapshots].
/// Returns empty for a UID that has not been primed yet - the graph fills in
/// on the frame after priming completes rather than blocking the first one.
List<StatSnapshot> loadSnapshotsSync({String? uid}) {
  final key = PrefsKeys.snapshotKeyFor(uid);
  final snaps = _cache[key];
  if (snaps == null) return const [];
  _remember(key, snaps); // a read counts as use
  return snaps;
}

/// Per-UID chain of in-flight [appendSnapshot] calls, so two interleaved
/// appends for the same UID can't both read the same pre-append list and
/// race to write `_cache[key]`, dropping one reading. Each call chains onto
/// the previous one before doing its own read-modify-write. Assigned
/// synchronously, before any await — the same idiom
/// `RankedHistoryStore._open()` uses for its memoized open.
final Map<String, Future<List<StatSnapshot>>> _appending = {};

/// Appends a reading for [uid], if it is one worth keeping.
///
/// Returns the updated list. Skips (returning the current list unchanged) when
/// the reading is an untrustworthy zero or a duplicate of the last one.
///
/// [staleAt], when non-null, says [stats] came from the response cache rather
/// than a live fetch. A cached copy is not a reading: it would be stamped *now*
/// while holding RP from up to a day ago, planting a fake drop (or gain) in the
/// series that the graph, the weekly delta and every backup then keep. Such a
/// call just returns the current list.
Future<List<StatSnapshot>> appendSnapshot(
  PlayerStats stats,
  RankedHistoryStore store, {
  String? uid,
  bool deduplicateRp = true,
  DateTime? staleAt,
}) {
  final key = PrefsKeys.snapshotKeyFor(uid);
  final previous = _appending[key];
  // Swallow a prior failure rather than propagate it - it was already
  // surfaced to its own caller, and chaining its rejection here would skip
  // our own write for an unrelated failure.
  final ready = previous == null
      ? Future<void>.value()
      : previous.then((_) {}, onError: (_) {});
  final chained = ready.then(
    (_) => _appendSnapshotLocked(
      stats,
      store,
      uid: uid,
      deduplicateRp: deduplicateRp,
      isStale: staleAt != null,
    ),
  );
  _appending[key] = chained;
  // Only the entry still pointing at *this* link is cleared — a newer call
  // may already have chained onto it and replaced the map entry.
  unawaited(
    chained
        .catchError((_, _) => const <StatSnapshot>[])
        .whenComplete(() {
          if (identical(_appending[key], chained)) _appending.remove(key);
        }),
  );
  return chained;
}

Future<List<StatSnapshot>> _appendSnapshotLocked(
  PlayerStats stats,
  RankedHistoryStore store, {
  String? uid,
  bool deduplicateRp = true,
  bool isStale = false,
}) async {
  final key = PrefsKeys.snapshotKeyFor(uid);
  // Read before any await, so a clear mid-append can't be undone below.
  final epoch = store.dataEpoch;
  // A UID that was never primed would otherwise dedup against an empty list
  // and re-append a reading already on disk.
  final snapshots = _cache.containsKey(key)
      ? _cache[key]!
      : await primeSnapshots(store, uid);

  // A cached copy isn't a reading (see [appendSnapshot]). Still primed above,
  // so the caller gets the series to draw.
  if (isStale) return snapshots;

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
  await store.appendSnapshotFor(uid ?? '', snapshot, onlyIfEpoch: epoch);
  // Cleared meanwhile, so the write was dropped — don't cache it as if it landed.
  if (store.dataEpoch != epoch) return snapshots;
  // One row appended, one list element appended - no full re-encode of the
  // series, which is what made the old prefs blob O(n) on every poll tick.
  final updated = [...snapshots, snapshot];
  _remember(key, updated);
  return updated;
}

/// Appends a snapshot and returns the updated list for `stats.uid`.
Future<List<StatSnapshot>> appendAndLoadSnapshots(
  PlayerStats stats,
  RankedHistoryStore store, {
  bool deduplicateRp = true,
  DateTime? staleAt,
}) => appendSnapshot(
  stats,
  store,
  uid: stats.uid,
  deduplicateRp: deduplicateRp,
  staleAt: staleAt,
);

/// Loads snapshots and seasons for a player in one call. Used by state
/// initialization in stats views to populate all snapshot-related data.
/// Reads the primed cache, so it stays synchronous.
({List<StatSnapshot> snapshots, Map<String, SeasonMeta> allSeasons})
initSnapshotsData(SharedPreferences prefs, String uid) {
  final snaps = loadSnapshotsSync(uid: uid);
  final seasons = loadAllSeasonsSync(prefs);
  return (snapshots: snaps, allSeasons: seasons);
}
