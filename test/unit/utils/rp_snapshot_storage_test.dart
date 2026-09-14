import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';
import 'package:apexlytics/utils/storage/rp_snapshot_storage.dart';
import 'package:apexlytics/utils/formatting/snapshot_types.dart';
import 'package:apexlytics/models/season_meta.dart';

import '../../helpers.dart';

/// A ranked split window; only the id matters for snapshot stamping.
SeasonMeta _split(String id) =>
    SeasonMeta.fromApi(id: id, startSeconds: 1000, endSeconds: 999999);

void main() {
  // sqflite has no native binding under `flutter test` (host VM) - use FFI.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late RankedHistoryStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    // The cache is process-wide, so one test's series would otherwise be
    // visible to the next.
    resetSnapshotCache();
  });

  tearDown(() => store.close());

  group('loadSnapshotsSync', () {
    test('returns empty for a UID that has not been primed', () {
      // Deliberately not an error: the first frame renders before the async
      // prime completes, and the graph fills in a frame later.
      expect(loadSnapshotsSync(uid: 'uid123'), isEmpty);
    });

    test('serves the primed series', () async {
      await store.appendSnapshotsFor('uid123', [
        StatSnapshot(timestamp: DateTime(2026, 9, 1), rp: 1500),
      ]);
      await primeSnapshots(store, 'uid123');

      final result = loadSnapshotsSync(uid: 'uid123');
      expect(result.length, 1);
      expect(result.first.rp, 1500);
    });

    test('keeps UIDs separate', () async {
      await appendSnapshot(buildStats(rankScore: 3000), store, uid: 'abc');
      expect(loadSnapshotsSync(uid: 'abc').length, 1);
      expect(loadSnapshotsSync(uid: 'other'), isEmpty);
    });

    test('returns snapshots oldest first', () async {
      await appendSnapshot(buildStats(rankScore: 100), store, uid: 'u');
      await appendSnapshot(buildStats(rankScore: 200), store, uid: 'u');
      await appendSnapshot(buildStats(rankScore: 300), store, uid: 'u');
      resetSnapshotCache();
      await primeSnapshots(store, 'u');

      // Every consumer assumes this: lastResetIndex walks backwards and
      // weekDelta takes `before.last`.
      expect(loadSnapshotsSync(uid: 'u').map((s) => s.rp), [100, 200, 300]);
    });
  });

  group('appendSnapshot', () {
    test('appends a new snapshot', () async {
      await appendSnapshot(buildStats(rankScore: 2400), store);
      final snaps = loadSnapshotsSync();
      expect(snaps.length, 1);
      expect(snaps.first.rp, 2400);
    });

    test('persists to the table, not just the cache', () async {
      await appendSnapshot(buildStats(rankScore: 2400), store, uid: 'u');
      resetSnapshotCache();
      expect((await primeSnapshots(store, 'u')).single.rp, 2400);
    });

    test('deduplicates when RP is unchanged', () async {
      final stats = buildStats(rankScore: 2400);
      await appendSnapshot(stats, store);
      await appendSnapshot(stats, store);
      expect(loadSnapshotsSync().length, 1);
    });

    test('does NOT deduplicate when deduplicateRp is false', () async {
      final stats = buildStats(rankScore: 2400);
      await appendSnapshot(stats, store, deduplicateRp: false);
      await appendSnapshot(stats, store, deduplicateRp: false);
      // Both land even though they share a millisecond - (uid, ts_ms) is the
      // primary key, so the second is nudged forward rather than replacing
      // the first.
      expect(loadSnapshotsSync().length, 2);
    });

    test('back-to-back appends keep strictly increasing timestamps', () async {
      for (var i = 0; i < 5; i++) {
        await appendSnapshot(buildStats(rankScore: 100 + i), store, uid: 'u');
      }
      resetSnapshotCache();
      final snaps = await primeSnapshots(store, 'u');
      expect(snaps.length, 5);
      for (var i = 1; i < snaps.length; i++) {
        expect(snaps[i].timestamp.isAfter(snaps[i - 1].timestamp), isTrue);
      }
    });

    test('appends when RP changes', () async {
      await appendSnapshot(buildStats(rankScore: 2400), store);
      await appendSnapshot(buildStats(rankScore: 2500), store);
      final snaps = loadSnapshotsSync();
      expect(snaps.length, 2);
      expect(snaps.last.rp, 2500);
    });

    test('stamps the current split id onto the snapshot', () async {
      await appendSnapshot(
        buildStats(rankScore: 4420, rankedSeason: _split('br_ranked_s30_s1')),
        store,
      );
      expect(loadSnapshotsSync().single.seasonId, 'br_ranked_s30_s1');
    });

    test('leaves the split id null when the season is unknown', () async {
      await appendSnapshot(buildStats(rankScore: 4420), store);
      expect(loadSnapshotsSync().single.seasonId, isNull);
    });

    test('appends across a split change even when RP is unchanged', () async {
      // This entry is what marks where the reset fell in the stream, so dedup
      // must not swallow it just because the RP number happens to repeat.
      await appendSnapshot(
        buildStats(rankScore: 4420, rankedSeason: _split('br_ranked_s29_s2')),
        store,
      );
      await appendSnapshot(
        buildStats(rankScore: 4420, rankedSeason: _split('br_ranked_s30_s1')),
        store,
      );
      final snaps = loadSnapshotsSync();
      expect(snaps.length, 2);
      expect(snaps.last.seasonId, 'br_ranked_s30_s1');
    });

    test('still deduplicates within the same split', () async {
      final stats = buildStats(
        rankScore: 4420,
        rankedSeason: _split('br_ranked_s30_s1'),
      );
      await appendSnapshot(stats, store);
      await appendSnapshot(stats, store);
      expect(loadSnapshotsSync().length, 1);
    });

    test('rejects a 0 reading once RP has been earned', () async {
      await appendSnapshot(buildStats(rankScore: 11998), store);
      await appendSnapshot(buildStats(rankScore: 0), store);
      final snaps = loadSnapshotsSync();
      expect(snaps.length, 1);
      expect(snaps.single.rp, 11998);
    });

    test('records 0 for a player who has never earned RP', () async {
      await appendSnapshot(buildStats(rankScore: 0), store);
      expect(loadSnapshotsSync().single.rp, 0);
    });

    test('dedups against the table when the UID was never primed', () async {
      await appendSnapshot(buildStats(rankScore: 2400), store, uid: 'u');
      // Simulates a fresh launch: rows on disk, cache cold.
      resetSnapshotCache();
      await appendSnapshot(buildStats(rankScore: 2400), store, uid: 'u');
      expect(await store.snapshotCount('u'), 1);
    });
  });

  group('migrateSnapshotsFromPrefs', () {
    Future<SharedPreferences> seedLegacy(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    String legacy(List<(int, int)> entries) => jsonEncode([
      for (final (ts, rp) in entries) {'ts': ts, 'rp': rp},
    ]);

    test(
      'drains a UID-scoped blob into the table and removes the key',
      () async {
        final prefs = await seedLegacy({
          'stat_snapshots_uid123': legacy([(1000, 100), (2000, 200)]),
        });

        await migrateSnapshotsFromPrefs(prefs, store);

        expect((await primeSnapshots(store, 'uid123')).map((s) => s.rp), [
          100,
          200,
        ]);
        expect(prefs.getString('stat_snapshots_uid123'), isNull);
      },
    );

    test('drains the legacy UID-less key under the empty-uid bucket', () async {
      final prefs = await seedLegacy({
        'stat_snapshots': legacy([(1000, 800)]),
      });

      await migrateSnapshotsFromPrefs(prefs, store);

      expect((await primeSnapshots(store, null)).single.rp, 800);
      expect(prefs.getString('stat_snapshots'), isNull);
    });

    test('is idempotent - a re-run cannot duplicate the series', () async {
      final prefs = await seedLegacy({
        'stat_snapshots_u': legacy([(1000, 100), (2000, 200)]),
      });

      await migrateSnapshotsFromPrefs(prefs, store);
      // Re-seed the same blob, as an interrupted or re-imported backup would.
      await prefs.setString(
        'stat_snapshots_u',
        legacy([(1000, 100), (2000, 200)]),
      );
      await migrateSnapshotsFromPrefs(prefs, store);

      expect(await store.snapshotCount('u'), 2);
    });

    test('is a no-op with no legacy keys', () async {
      final prefs = await seedLegacy({'unrelated': 'x'});
      await migrateSnapshotsFromPrefs(prefs, store);
      expect(prefs.getString('unrelated'), 'x');
    });

    test('drains keys restored later by a v1/v2 backup import', () async {
      // Key-driven rather than flag-driven precisely so this works: a
      // "migrated" flag set on first launch would suppress it forever.
      final prefs = await seedLegacy({});
      await migrateSnapshotsFromPrefs(prefs, store);

      await prefs.setString('stat_snapshots_u', legacy([(3000, 300)]));
      await migrateSnapshotsFromPrefs(prefs, store);

      expect((await primeSnapshots(store, 'u')).single.rp, 300);
    });

    test('corrupt legacy JSON is skipped, not fatal', () async {
      final prefs = await seedLegacy({'stat_snapshots_u': 'not json'});
      await migrateSnapshotsFromPrefs(prefs, store);
      expect(await store.snapshotCount('u'), 0);
    });

    test(
      'an unreadable blob is kept, not deleted, so it can be recovered',
      () async {
        final prefs = await seedLegacy({'stat_snapshots_u': 'not json'});
        await migrateSnapshotsFromPrefs(prefs, store);
        // Deleting an unparseable blob would destroy the only copy of that
        // player's RP history with no recovery path - only a genuinely empty
        // blob is safe to remove.
        expect(prefs.getString('stat_snapshots_u'), 'not json');
      },
    );

    test(
      'a well-formed but wrong-shape blob does not abort draining other keys',
      () async {
        final prefs = await seedLegacy({
          // Valid JSON, but not a list - throws TypeError on the old `as
          // List` cast, which only caught FormatException.
          'stat_snapshots_bad': '{"a":1}',
          'stat_snapshots_good': legacy([(1000, 100)]),
        });

        await migrateSnapshotsFromPrefs(prefs, store);

        expect((await primeSnapshots(store, 'good')).single.rp, 100);
        expect(prefs.getString('stat_snapshots_good'), isNull);
        expect(prefs.getString('stat_snapshots_bad'), '{"a":1}');
      },
    );
  });

  group('computeDelta', () {
    test('returns null for empty snapshot list', () {
      expect(computeDelta([], 1000), isNull);
    });

    test('returns current minus oldest when all snapshots are within 24h', () {
      final now = DateTime.now();
      final snaps = [
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 2)),
          rp: 1000,
        ),
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 1)),
          rp: 1200,
        ),
      ];
      expect(computeDelta(snaps, 1300), 300);
    });

    test('uses most-recent snapshot older than 24h as baseline', () {
      final now = DateTime.now();
      final snaps = [
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 48)),
          rp: 800,
        ),
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 25)),
          rp: 1000,
        ),
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 1)),
          rp: 1300,
        ),
      ];
      // Baseline = most recent before 24h = 1000
      expect(computeDelta(snaps, 1400), 400);
    });

    test('handles negative delta (demotion)', () {
      final now = DateTime.now();
      final snaps = [
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 25)),
          rp: 2000,
        ),
      ];
      expect(computeDelta(snaps, 1800), -200);
    });
  });
}
