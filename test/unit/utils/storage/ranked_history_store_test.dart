import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/utils/formatting/season_utils.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';

void main() {
  // sqflite has no native binding under `flutter test` (host VM) — use FFI.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // fromApi takes Unix seconds; match end = start + 600s (see [match]).
  SeasonMeta season(String id, int startSecs, int endSecs) =>
      SeasonMeta.fromApi(id: id, startSeconds: startSecs, endSeconds: endSecs);

  RankedMatch match(
    String uid,
    int startSecs, {
    String legend = 'Axle',
    int rp = 10,
    String mapKey = 'olympus_rotation',
  }) => RankedMatch.fromJson({
    'uid': uid,
    'name': 'Tester',
    'legendPlayed': legend,
    'gameMode': 'BATTLE_ROYALE',
    'gameLengthSecs': 600,
    'gameStartTimestamp': startSecs,
    'gameEndTimestamp': startSecs + 600,
    'gameData': [
      {'key': 'kills', 'value': 3, 'name': 'BR Kills'},
      {'key': 'damage', 'value': 1000, 'name': 'BR Damage'},
    ],
    'BRScoreChange': rp,
    'BRScore': 1000,
    'map': mapKey,
  });

  test('persists matches and returns them newest first', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    await store.upsertAll('1', [
      match('1', 100),
      match('1', 300),
      match('1', 200),
    ]);

    final all = await store.getAll('1');
    expect(all.length, 3);
    expect(all.first.startTime.millisecondsSinceEpoch, 300 * 1000);
    expect(all.last.startTime.millisecondsSinceEpoch, 100 * 1000);
  });

  test('dedupes overlapping matches across re-fetches (idempotent)', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    await store.upsertAll('1', [match('1', 100), match('1', 200)]);
    // Second fetch overlaps on 200 and adds 300 — the API window rolled forward.
    await store.upsertAll('1', [match('1', 200), match('1', 300)]);

    expect(await store.count('1'), 3); // 100, 200, 300 — no duplicate
  });

  test('keeps each UID history separate', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    await store.upsertAll('1', [match('1', 100)]);
    await store.upsertAll('2', [match('2', 100), match('2', 200)]);

    expect(await store.count('1'), 1);
    expect(await store.count('2'), 2);
    expect((await store.getAll('1')).single.uid, '1');
  });

  test(
    'export rows import into a fresh store (single-file migration)',
    () async {
      final source = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      await source.upsertAll('1', [
        match('1', 100, legend: 'Wraith'),
        match('1', 200),
      ]);
      final rows = await source.exportRows();
      await source.close();

      final restored = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(restored.close);
      await restored.importRows(rows);

      final all = await restored.getAll('1');
      expect(all.length, 2);
      expect(all.any((m) => m.legend == 'Wraith'), true);
    },
  );

  test('stamps season_id on upsert and enumerates via seasonCounts', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    final seasons = {
      's1': season('br_ranked_s1_s1', 0, 1000), // ends within [0, 1_000_000ms)
      's2': season('br_ranked_s1_s2', 1000, 2000), // [1_000_000, 2_000_000ms)
    };
    await store.upsertAll('1', [
      match('1', 100), // end 700_000ms → s1
      match('1', 300), // end 900_000ms → s1
      match('1', 1100), // end 1_700_000ms → s2
    ], seasons: seasons);

    final counts = await store.seasonCounts('1');
    expect(counts['br_ranked_s1_s1'], 2);
    expect(counts['br_ranked_s1_s2'], 1);
  });

  test(
    'rankedSeasonCounts counts ranked-only and folds NULL into Unknown',
    () async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);

      final seasons = {'s1': season('br_ranked_s1_s1', 0, 1000)};
      await store.upsertAll('1', [
        match('1', 100), // end 700_000ms → s1 (ranked)
        match('1', 300), // → s1 (ranked)
        match('1', 200, rp: 0), // pub in s1 — excluded
      ], seasons: seasons);
      // Written with no season metadata → season_id left NULL.
      await store.upsertAll('1', [match('1', 5000)]);

      final counts = await store.rankedSeasonCounts('1');
      expect(counts['br_ranked_s1_s1'], 2); // pub not counted
      expect(counts[kUnknownSeasonId], 1); // NULL folded into Unknown
    },
  );

  test('getBySeason returns one split; Unknown includes NULL rows', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    final seasons = {
      's1': season('br_ranked_s1_s1', 0, 1000),
      's2': season('br_ranked_s1_s2', 1000, 2000),
    };
    await store.upsertAll('1', [
      match('1', 100), // → s1
      match('1', 1100), // → s2
    ], seasons: seasons);
    await store.upsertAll('1', [match('1', 5000)]); // NULL season

    final s1 = await store.getBySeason('1', 'br_ranked_s1_s1');
    expect(s1.length, 1);
    expect(s1.single.seasonId, 'br_ranked_s1_s1');

    final unknown = await store.getBySeason('1', kUnknownSeasonId);
    expect(unknown.length, 1); // the NULL-season row folds in
  });

  test('matches outside every known season are stamped Unknown', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    await store.upsertAll(
      '1',
      [match('1', 5000)], // end 5_600_000ms, outside the season below
      seasons: {'s1': season('br_ranked_s1_s1', 0, 1000)},
    );

    expect((await store.seasonCounts('1'))[kUnknownSeasonId], 1);
  });

  test('a real season_id is never overwritten by a later re-sync', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    await store.upsertAll(
      '1',
      [match('1', 100)], // end 700_000ms
      seasons: {'s1': season('br_ranked_s1_s1', 0, 1000)},
    );
    expect((await store.seasonCounts('1'))['br_ranked_s1_s1'], 1);

    // Re-synced (e.g. still in the API's rolling window) with no season
    // metadata this call — must not blank the existing classification.
    await store.upsertAll('1', [match('1', 100)]);
    expect((await store.seasonCounts('1'))['br_ranked_s1_s1'], 1);

    // Re-synced with a season map that would derive a *different* answer —
    // still must not downgrade an already-real classification.
    await store.upsertAll(
      '1',
      [match('1', 100)],
      seasons: {'s2': season('br_ranked_s2_s1', 5000, 6000)},
    );
    expect((await store.seasonCounts('1'))['br_ranked_s1_s1'], 1);
  });

  test(
    'backfillSeasonIds classifies rows written without season metadata',
    () async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);

      // No seasons passed → season_id left NULL (omitted from seasonCounts).
      await store.upsertAll('1', [match('1', 100), match('1', 300)]);
      expect(await store.seasonCounts('1'), isEmpty);

      await store.backfillSeasonIds({'s1': season('br_ranked_s1_s1', 0, 1000)});
      expect((await store.seasonCounts('1'))['br_ranked_s1_s1'], 2);
    },
  );

  test('backfillSeasonIds reclassifies rows previously stamped Unknown once '
      'their season becomes known', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    // Written before the split's window was cached → stamped Unknown.
    await store.upsertAll(
      '1',
      [match('1', 500)], // end 1_100_000ms
      seasons: {'other': season('br_ranked_other', 0, 100)},
    );
    expect((await store.seasonCounts('1'))[kUnknownSeasonId], 1);

    // The split's window is now known → backfill should self-correct it.
    await store.backfillSeasonIds({'s1': season('br_ranked_s1_s1', 0, 2000)});
    final counts = await store.seasonCounts('1');
    expect(counts['br_ranked_s1_s1'], 1);
    expect(counts[kUnknownSeasonId], isNull);
  });

  test(
    'migrates a v1 database by adding season_id (rows preserved, NULL)',
    () async {
      final dir = await Directory.systemTemp.createTemp('rhs_mig');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'ranked_history.db');

      // Build a v1-schema database (no season_id column) and seed one row.
      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE ranked_matches (
              id TEXT PRIMARY KEY, uid TEXT NOT NULL, player_name TEXT,
              legend TEXT, game_mode TEXT, map_key TEXT, rp_change INTEGER,
              cumulative_rp INTEGER, rank_img TEXT, length_secs INTEGER,
              start_ms INTEGER, end_ms INTEGER, is_party_full INTEGER,
              trackers TEXT
            )
          ''');
          },
        ),
      );
      await v1.insert('ranked_matches', match('1', 100).toStoredMap());
      await v1.close();

      // Reopen through the store (version 2) → triggers onUpgrade.
      final store = RankedHistoryStore(overridePath: path);
      addTearDown(store.close);
      expect(await store.count('1'), 1); // row survived the migration
      expect(
        await store.seasonCounts('1'),
        isEmpty,
      ); // season_id NULL until backfill

      await store.backfillSeasonIds({'s1': season('br_ranked_s1_s1', 0, 1000)});
      expect((await store.seasonCounts('1'))['br_ranked_s1_s1'], 1);
    },
  );

  test('upsertAll denormalizes kills/damage into columns', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    await store.upsertAll('1', [match('1', 100)]);

    // exportRows does SELECT * — the raw column values, not the model getters
    // (which derive from trackers regardless of the column).
    final row = (await store.exportRows()).single;
    expect(row['kills'], 3);
    expect(row['damage'], 1000);
  });

  test(
    'migrates a v2 database by adding kills/damage, backfilled from trackers',
    () async {
      final dir = await Directory.systemTemp.createTemp('rhs_mig3');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'ranked_history.db');

      // Build a v2-schema database (season_id present, no kills/damage columns).
      final v2 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE ranked_matches (
              id TEXT PRIMARY KEY, uid TEXT NOT NULL, player_name TEXT,
              legend TEXT, game_mode TEXT, map_key TEXT, rp_change INTEGER,
              cumulative_rp INTEGER, rank_img TEXT, length_secs INTEGER,
              start_ms INTEGER, end_ms INTEGER, is_party_full INTEGER,
              trackers TEXT, season_id TEXT
            )
          ''');
          },
        ),
      );
      await v2.insert('ranked_matches', match('1', 100).toStoredMap());
      await v2.close();

      // Reopen through the store (version 3) → onUpgrade adds the columns NULL.
      final store = RankedHistoryStore(overridePath: path);
      addTearDown(store.close);
      expect((await store.exportRows()).single['kills'], isNull);

      await store.backfillKillsDamage();
      final row = (await store.exportRows()).single;
      expect(row['kills'], 3);
      expect(row['damage'], 1000);
    },
  );

  group('SQL aggregation parity with the Dart aggregates', () {
    void expectSummaryEq(RankedSummary a, RankedSummary b) {
      expect(a.games, b.games);
      expect(a.netRp, b.netRp);
      expect(a.currentRp, b.currentRp);
      expect(a.totalKills, b.totalKills);
      expect(a.totalDamage, b.totalDamage);
      expect(a.totalLengthSecs, b.totalLengthSecs);
      expect(a.wins, b.wins);
      expect(a.losses, b.losses);
    }

    Future<RankedHistoryStore> seeded() async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      final seasons = {
        's1': season('br_ranked_s1_s1', 0, 1000),
        's2': season('br_ranked_s1_s2', 1000, 2000),
      };
      await store.upsertAll('1', [
        match('1', 100, legend: 'Axle', rp: 40), // s1, olympus, win
        match('1', 200, legend: 'Axle', rp: -20), // s1, olympus, loss
        match(
          '1',
          300,
          legend: 'Bangalore',
          mapKey: 'storm_point_rotation',
          rp: 60,
        ), // s1
        match('1', 350, legend: 'Axle', rp: 1500), // s1, reset outlier
        match(
          '1',
          250,
          legend: 'Bangalore',
          mapKey: 'storm_point_rotation',
          rp: 0,
        ), // pub
        match('1', 1100, legend: 'Axle', rp: 15), // s2, olympus, win
        match('1', 1200, legend: 'Bangalore', rp: -30), // s2, olympus, loss
      ], seasons: seasons);
      return store;
    }

    test('lifetime summary/legends/maps match the Dart path', () async {
      final store = await seeded();
      addTearDown(store.close);
      final ranked = rankedOnly(await store.getAll('1'));

      expectSummaryEq(await store.summaryFor('1'), summarize(ranked));

      final sqlLegends = await store.legendBreakdownsFor('1');
      final dartLegends = {
        for (final l in legendBreakdowns(ranked)) l.legend: l,
      };
      expect(sqlLegends.length, dartLegends.length);
      for (final s in sqlLegends) {
        final d = dartLegends[s.legend]!;
        expect(s.games, d.games);
        expect(s.totalRp, d.totalRp);
        expect(s.totalKills, d.totalKills);
        expect(s.totalDamage, d.totalDamage);
        expect(s.totalLengthSecs, d.totalLengthSecs);
        expect(s.wins, d.wins);
        expect(s.losses, d.losses);
      }
      // Highest-RP legend sorts first (Axle 35 > Bangalore 30).
      expect(sqlLegends.first.legend, 'Axle');

      final sqlMaps = await store.mapBreakdownsFor('1');
      final dartMaps = {for (final m in mapBreakdowns(ranked)) m.mapKey: m};
      expect(sqlMaps.length, dartMaps.length);
      for (final s in sqlMaps) {
        final d = dartMaps[s.mapKey]!;
        expect(s.displayName, d.displayName);
        expect(s.games, d.games);
        expect(s.totalRp, d.totalRp);
        expect(s.wins, d.wins);
        expect(s.losses, d.losses);
      }
      // Most-played map sorts first (olympus 5 > storm point 1).
      expect(sqlMaps.first.mapKey, 'olympus_rotation');
    });

    test('per-split summary matches the Dart path for that split', () async {
      final store = await seeded();
      addTearDown(store.close);
      final s2 = rankedOnly(await store.getBySeason('1', 'br_ranked_s1_s2'));
      expectSummaryEq(
        await store.summaryFor('1', seasonId: 'br_ranked_s1_s2'),
        summarize(s2),
      );
    });

    test('empty scope returns the empty summary', () async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);
      expectSummaryEq(await store.summaryFor('nobody'), RankedSummary.empty);
    });

    test('matchesForLegend / matchesForMap return one ranked entity', () async {
      final store = await seeded();
      addTearDown(store.close);

      final axle = await store.matchesForLegend('1', 'Axle');
      expect(axle.every((m) => m.legend == 'Axle' && m.isRanked), true);
      expect(axle.length, 4); // 3 real + 1 reset outlier, all ranked

      final storm = await store.matchesForMap('1', 'storm_point_rotation');
      expect(storm.every((m) => m.mapKey == 'storm_point_rotation'), true);
      expect(storm.length, 1); // the pub (0 RP) is excluded
    });

    test(
      'timeOfDayBucketsFor (lifetime and per-split) matches the Dart path',
      () async {
        final store = await seeded();
        addTearDown(store.close);

        final allRanked = rankedOnly(await store.getAll('1'));
        final sqlLifetime = await store.timeOfDayBucketsFor('1');
        final dartLifetime = timeOfDayBuckets(allRanked);
        expect(
          sqlLifetime.map((b) => (b.hourLocal, b.games, b.netRp)).toList(),
          dartLifetime.map((b) => (b.hourLocal, b.games, b.netRp)).toList(),
        );

        final s1Ranked = rankedOnly(
          await store.getBySeason('1', 'br_ranked_s1_s1'),
        );
        final sqlSplit = await store.timeOfDayBucketsFor(
          '1',
          seasonId: 'br_ranked_s1_s1',
        );
        final dartSplit = timeOfDayBuckets(s1Ranked);
        expect(
          sqlSplit.map((b) => (b.hourLocal, b.games, b.netRp)).toList(),
          dartSplit.map((b) => (b.hourLocal, b.games, b.netRp)).toList(),
        );
      },
    );
  });

  group('lazy backfills are served by partial indexes, not a full scan', () {
    late Directory tmpDir;
    late String dbPath;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('ranked_idx');
      dbPath = p.join(tmpDir.path, 'ranked.db');
    });
    tearDown(() => tmpDir.deleteSync(recursive: true));

    // The whole reason the backfill predicates are shared constants is so their
    // partial indexes stay applicable. If a predicate ever drifts from its index
    // the query silently falls back to scanning every row — this asserts the
    // planner actually searches the index instead.
    Future<String> planFor(String where) async {
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      try {
        final plan = await db.rawQuery(
          'EXPLAIN QUERY PLAN SELECT id FROM ${RankedHistoryStore.table} '
          'WHERE $where',
        );
        return plan.map((r) => r['detail']).join(' | ');
      } finally {
        await db.close();
      }
    }

    test('kills/damage and season-id backfills both use their index', () async {
      final store = RankedHistoryStore(overridePath: dbPath);
      await store.upsertAll('1', [match('1', 100), match('1', 200)]);
      await store.close(); // flush schema + rows to the file for a 2nd connection

      expect(
        await planFor('kills IS NULL OR damage IS NULL'),
        contains('idx_needs_kills_damage'),
      );
      expect(
        await planFor("season_id IS NULL OR season_id = '$kUnknownSeasonId'"),
        contains('idx_needs_season_id'),
      );
    });

    test('the ranked-scope aggregate query uses idx_ranked_scope', () async {
      final store = RankedHistoryStore(overridePath: dbPath);
      await store.upsertAll('1', [match('1', 100), match('1', 200)]);
      await store.close();

      // The shared WHERE prefix of summaryFor/legendBreakdownsFor/etc.
      expect(
        await planFor(
          "uid = '1' AND game_mode = 'BATTLE_ROYALE' AND rp_change != 0",
        ),
        contains('idx_ranked_scope'),
      );
    });
  });
}
