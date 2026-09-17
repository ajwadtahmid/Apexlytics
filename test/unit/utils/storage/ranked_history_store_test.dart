import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/utils/formatting/season_utils.dart';
import 'package:apexlytics/utils/formatting/snapshot_types.dart';
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
    bool isPartyFull = false,
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
    'isPartyFull': isPartyFull,
  });

  /// [m] as a row carrying only [columns], for inserting into the deliberately
  /// older schemas the migration tests build.
  Map<String, Object?> rowFor(RankedMatch m, Set<String> columns) => {
    for (final e in m.toStoredMap().entries)
      if (columns.contains(e.key)) e.key: e.value,
  };

  const v1Columns = {
    'id',
    'uid',
    'player_name',
    'legend',
    'game_mode',
    'map_key',
    'rp_change',
    'cumulative_rp',
    'rank_img',
    'length_secs',
    'start_ms',
    'end_ms',
    'is_party_full',
    'trackers',
  };
  const v2Columns = {...v1Columns, 'season_id'};
  const v3Columns = {...v2Columns, 'kills', 'damage'};

  /// A match upstream served with an empty `gameData` — a real and fairly
  /// common shape, and the reason kills/damage have to be nullable.
  RankedMatch untracked(String uid, int startSecs, {int rp = 10}) =>
      RankedMatch.fromJson({
        'uid': uid,
        'name': 'Tester',
        'legendPlayed': 'Axle',
        'gameMode': 'BATTLE_ROYALE',
        'gameLengthSecs': 600,
        'gameStartTimestamp': startSecs,
        'gameEndTimestamp': startSecs + 600,
        'gameData': const [],
        'BRScoreChange': rp,
        'BRScore': 1000,
        'map': 'olympus_rotation',
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

  test('allIds returns every stored id, across all UIDs', () async {
    // Backs the backup-import preview, which needs to tell a restored row
    // from an already-known one by id.
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    await store.upsertAll('1', [match('1', 100), match('1', 200)]);
    await store.upsertAll('2', [match('2', 100)]);

    expect(await store.allIds(), {'1_100', '1_200', '2_100'});
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
      await v1.insert('ranked_matches', rowFor(match('1', 100), v1Columns));
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
      await v2.insert('ranked_matches', rowFor(match('1', 100), v2Columns));
      await v2.close();

      // Reopening through the store runs every migration, ending with the v6
      // repair that derives kills/damage from each row's trackers blob.
      final store = RankedHistoryStore(overridePath: path);
      addTearDown(store.close);

      final row = (await store.exportRows()).single;
      expect(row['kills'], 3);
      expect(row['damage'], 1000);
    },
  );

  test(
    'the v6 repair writes null for a match that carried no trackers',
    () async {
      final dir = await Directory.systemTemp.createTemp('rhs_mig6');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'ranked_history.db');

      // A v3 database whose backfill wrote 0 for an unreported stat.
      final v3 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE ranked_matches (
              id TEXT PRIMARY KEY, uid TEXT NOT NULL, player_name TEXT,
              legend TEXT, game_mode TEXT, map_key TEXT, rp_change INTEGER,
              cumulative_rp INTEGER, rank_img TEXT, length_secs INTEGER,
              start_ms INTEGER, end_ms INTEGER, is_party_full INTEGER,
              trackers TEXT, season_id TEXT, kills INTEGER, damage INTEGER
            )
          ''');
          },
        ),
      );
      await v3.insert('ranked_matches', {
        ...rowFor(untracked('1', 100), v3Columns),
        'kills': 0,
        'damage': 0,
      });
      await v3.close();

      final store = RankedHistoryStore(overridePath: path);
      addTearDown(store.close);

      final row = (await store.exportRows()).single;
      expect(row['kills'], isNull, reason: 'an empty blob means unreported');
      expect(row['damage'], isNull);
    },
  );

  test(
    'upgrading a v7 database adds the snapshot table and keeps matches',
    () async {
      final dir = await Directory.systemTemp.createTemp('rhs_mig8');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'ranked_history.db');

      // A v7 database: every match column, no stat_snapshots table.
      final v7 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE ranked_matches (
              id TEXT PRIMARY KEY, uid TEXT NOT NULL, player_name TEXT,
              legend TEXT, game_mode TEXT, map_key TEXT, rp_change INTEGER,
              cumulative_rp INTEGER, rank_img TEXT, length_secs INTEGER,
              start_ms INTEGER, end_ms INTEGER, is_party_full INTEGER,
              trackers TEXT, season_id TEXT, kills INTEGER, damage INTEGER,
              edited_fields TEXT
            )
          ''');
          },
        ),
      );
      await v7.insert('ranked_matches', match('1', 100).toStoredMap());
      await v7.close();

      final store = RankedHistoryStore(overridePath: path);
      addTearDown(store.close);

      // The new table exists and is usable...
      expect(await store.snapshotCount('1'), 0);
      await store.appendSnapshotFor(
        '1',
        StatSnapshot(timestamp: DateTime(2026, 9, 1), rp: 1200),
      );
      expect((await store.snapshotsFor('1')).single.rp, 1200);
      // ...and the upgrade didn't disturb the existing match history.
      expect(await store.count('1'), 1);
    },
  );

  group('importRows hardening (the file comes from the user)', () {
    test('an unknown key does not fail the whole restore', () async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);
      final good = match('1', 100).toStoredMap();

      await store.importRows([
        {...good, 'not_a_column': 'x'},
      ]);

      // Unfiltered, this reached SQLite as a column name and raised
      // "no such column", failing every row in the batch.
      expect(await store.count('1'), 1);
    });

    test('a row without an id is skipped rather than duplicated', () async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);
      final noId = Map<String, Object?>.from(match('1', 100).toStoredMap())
        ..remove('id');

      await store.importRows([noId, noId]);

      // SQLite allows NULL in a non-INTEGER PRIMARY KEY, so these used to
      // insert as two undeduplicatable rows.
      expect(await store.count('1'), 0);
    });

    test('a valid export still round-trips intact', () async {
      final source = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      await source.upsertAll('1', [match('1', 100, legend: 'Wraith')]);
      await source.editMatch('1_100', {'kills': 7});
      final rows = await source.exportRows();
      await source.close();

      final restored = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(restored.close);
      await restored.importRows(rows);

      final m = (await restored.getAll('1')).single;
      expect(m.legend, 'Wraith');
      expect(m.kills, 7);
      expect(m.editedFields, {'kills'});
    });

    test(
      'importing over an existing edited, classified row keeps the '
      'correction and does not demote its season_id',
      () async {
        // Used to be a plain INSERT OR REPLACE (delete-then-insert), so any
        // column absent from the incoming row — season_id on an export from
        // before that column existed, or a hand correction the backup
        // predates — silently reverted to NULL/unedited.
        final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
        addTearDown(store.close);
        final seasons = {'s1': season('br_ranked_s1_s1', 0, 1000)};
        await store.upsertAll('1', [match('1', 100)], seasons: seasons);
        await store.editMatch('1_100', {'kills': 99});

        // A stale backup row: same id, but the pre-edit kills value and no
        // season_id at all (the shape `toStoredMap()` produces — season_id
        // is derived separately by upsertAll, never stored on the model).
        final staleRow = match('1', 100).toStoredMap();
        await store.importRows([staleRow]);

        final m = (await store.getAll('1')).single;
        expect(m.kills, 99); // the correction survived the import
        expect(m.editedFields, {'kills'});
        expect(m.seasonId, 'br_ranked_s1_s1'); // not demoted back to null
      },
    );
  });

  group('importBackupData', () {
    test('matches and snapshots both commit together', () async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);

      await store.importBackupData(
        matchRows: [match('1', 100).toStoredMap()],
        snapshotRows: [
          {'uid': '1', 'ts_ms': 500, 'rp': 1200, 'season_id': null},
        ],
      );

      expect(await store.count('1'), 1);
      expect(await store.snapshotCount('1'), 1);
    });

    test(
      'a failure in one half rolls back both — neither table keeps a '
      'partial import',
      () async {
        final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
        addTearDown(store.close);
        // Pre-existing data, untouched by the failed import below — proves
        // the rollback doesn't wipe anything beyond what the import itself
        // would have written.
        await store.upsertAll('1', [match('1', 0)]);

        // A raw Map isn't a type sqflite can bind as a SQL argument — this
        // throws when the batch commits, which is what should trigger the
        // whole transaction to roll back.
        final badMatchRow = {
          ...match('1', 100).toStoredMap(),
          'rp_change': {'not': 'bindable'},
        };

        await expectLater(
          () => store.importBackupData(
            matchRows: [badMatchRow],
            snapshotRows: [
              {'uid': '1', 'ts_ms': 500, 'rp': 1200, 'season_id': null},
            ],
          ),
          throwsA(anything),
        );

        // The failed match row never landed...
        expect(await store.count('1'), 1); // only the pre-existing row
        // ...and neither did the snapshot row that came after it in the
        // same transaction, even though importSnapshotRows itself would
        // have succeeded in isolation.
        expect(await store.snapshotCount('1'), 0);
      },
    );
  });

  group('forEachRowInBatches', () {
    test(
      'visits every row across multiple pages, surviving rows dropping '
      'out of `where` as they are fixed mid-pass',
      () async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        addTearDown(db.close);
        await db.execute(
          'CREATE TABLE t (id TEXT PRIMARY KEY, fixed INTEGER NOT NULL)',
        );
        // 12 rows needing "fixing", paged 5 at a time — exercises more than
        // one full page and a partial last page (12 % 5 != 0).
        final seed = db.batch();
        for (var i = 0; i < 12; i++) {
          seed.insert('t', {'id': 'id$i', 'fixed': 0});
        }
        await seed.commit(noResult: true);

        final visited = <String>[];
        await RankedHistoryStore.forEachRowInBatches(
          db,
          't',
          columns: ['fixed'],
          where: 'fixed = 0', // shrinks as rows get "fixed" below
          batchSize: 5,
          apply: (batch, row) {
            visited.add(row['id'] as String);
            // Mutating the row so it stops matching `where` mid-pass is
            // exactly the hazard OFFSET pagination gets wrong: if this
            // method paged by OFFSET instead of by id, the next page's
            // OFFSET would skip rows shifted earlier by this update.
            batch.update(
              't',
              {'fixed': 1},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          },
        );

        expect(visited.length, 12);
        expect(visited.toSet(), {for (var i = 0; i < 12; i++) 'id$i'});
        expect(await db.query('t', where: 'fixed = 0'), isEmpty);
      },
    );

    test('an empty table is a no-op', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE t (id TEXT PRIMARY KEY)');

      var calls = 0;
      await RankedHistoryStore.forEachRowInBatches(
        db,
        't',
        columns: const [],
        apply: (batch, row) => calls++,
      );

      expect(calls, 0);
    });

    test('a page exactly the size of batchSize does not loop forever', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE t (id TEXT PRIMARY KEY)');
      final seed = db.batch();
      for (var i = 0; i < 5; i++) {
        seed.insert('t', {'id': 'id$i'});
      }
      await seed.commit(noResult: true);

      var calls = 0;
      await RankedHistoryStore.forEachRowInBatches(
        db,
        't',
        columns: const [],
        batchSize: 5,
        apply: (batch, row) => calls++,
      );

      expect(calls, 5);
    });
  });

  test('deleteAll drops snapshots as well as matches', () async {
    // "Clear all data" promises everything; RP snapshots are the app's other
    // record of the player's history and used to survive it entirely.
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);
    await store.upsertAll('1', [match('1', 100)]);
    await store.appendSnapshotFor(
      '1',
      StatSnapshot(timestamp: DateTime(2026, 9, 1), rp: 1200),
    );

    await store.deleteAll();

    expect(await store.count('1'), 0);
    expect(await store.snapshotCount('1'), 0);
  });

  group('hand-edited matches', () {
    Future<RankedHistoryStore> storeWithMatch(RankedMatch m) async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.upsertAll(m.uid, [m]);
      return store;
    }

    test('editMatch writes the value and flags the column', () async {
      final m = untracked('1', 100);
      final store = await storeWithMatch(m);

      await store.editMatch(m.dedupKey, {'kills': 4, 'damage': 1500});

      final stored = (await store.getAll('1')).single;
      expect(stored.kills, 4);
      expect(stored.damage, 1500);
      expect(stored.editedFields, {'damage', 'kills'});
    });

    test('a later sync leaves edited columns alone', () async {
      final m = match('1', 100); // upstream reports 3 kills / 1000 damage
      final store = await storeWithMatch(m);

      await store.editMatch(m.dedupKey, {'kills': 9});
      await store.upsertAll('1', [m]); // same match served again

      final stored = (await store.getAll('1')).single;
      expect(stored.kills, 9, reason: 'the correction must survive');
      expect(stored.damage, 1000, reason: 'unedited columns still refresh');
    });

    test('re-syncing an edited match never creates a second row', () async {
      final m = match('1', 100);
      final store = await storeWithMatch(m);

      await store.editMatch(m.dedupKey, {'legend': 'Wraith'});
      await store.upsertAll('1', [m]);
      await store.upsertAll('1', [m]);

      expect(await store.count('1'), 1);
      expect((await store.getAll('1')).single.legend, 'Wraith');
    });

    test('editing keeps the row id it was created with', () async {
      final m = match('1', 100);
      final store = await storeWithMatch(m);
      final originalId = m.dedupKey;

      await store.editMatch(originalId, {'rp_change': 42});

      final rows = await store.exportRows();
      expect(rows.single['id'], originalId);
      expect(rows.single['rp_change'], 42);
    });

    test('length_secs is not editable', () async {
      final m = match('1', 100);
      final store = await storeWithMatch(m);

      expect(
        () => store.editMatch(m.dedupKey, {'length_secs': 42}),
        throwsArgumentError,
      );
    });

    test('clearEdits lets the next sync overwrite the column again', () async {
      final m = match('1', 100);
      final store = await storeWithMatch(m);

      await store.editMatch(m.dedupKey, {'kills': 9});
      await store.clearEdits(m.dedupKey, field: 'kills');
      await store.upsertAll('1', [m]);

      final stored = (await store.getAll('1')).single;
      expect(stored.kills, 3);
      expect(stored.isEdited, isFalse);
    });

    test('clearEdits with no field drops every flag', () async {
      final m = match('1', 100);
      final store = await storeWithMatch(m);

      await store.editMatch(m.dedupKey, {'kills': 9, 'legend': 'Wraith'});
      await store.clearEdits(m.dedupKey);

      expect((await store.getAll('1')).single.isEdited, isFalse);
    });

    test('a non-editable column is rejected', () async {
      final m = match('1', 100);
      final store = await storeWithMatch(m);

      expect(
        () => store.editMatch(m.dedupKey, {'uid': '2'}),
        throwsArgumentError,
      );
    });

    test('editing an unknown match is a no-op and reports failure', () async {
      final store = await storeWithMatch(match('1', 100));
      final saved = await store.editMatch('nope', {'kills': 1});
      expect(saved, false);
      expect(await store.count('1'), 1);
    });

    test('editing a known match reports success', () async {
      final m = match('1', 100);
      final store = await storeWithMatch(m);
      expect(await store.editMatch(m.dedupKey, {'kills': 9}), true);
    });
  });

  test('aggregates skip unreported kills but keep the game', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);
    // Two matches with 3 kills each, one with no tracker at all.
    await store.upsertAll('1', [
      match('1', 100),
      match('1', 2000),
      untracked('1', 4000),
    ]);

    final summary = await store.summaryFor('1');
    expect(summary.games, 3, reason: 'the unreported game was still played');
    expect(summary.killsGames, 2);
    expect(summary.totalKills, 6);
    expect(summary.avgKills, 3.0, reason: 'divided by 2, not 3');
  });

  group('netRpInWindow', () {
    // Window spanning matches at t=2000s onwards (each match ends 600s later).
    final windowStart = DateTime.fromMillisecondsSinceEpoch(1500 * 1000);
    final windowEnd = DateTime.fromMillisecondsSinceEpoch(9000 * 1000);

    /// A match carrying an explicit running total, so the completeness chain
    /// (`cum == prevCum + rpChange`) can be set up or deliberately broken.
    RankedMatch chained(int startSecs, {required int rp, required int cum}) =>
        RankedMatch.fromJson({
          'uid': '1',
          'name': 'Tester',
          'legendPlayed': 'Axle',
          'gameMode': 'BATTLE_ROYALE',
          'gameLengthSecs': 600,
          'gameStartTimestamp': startSecs,
          'gameEndTimestamp': startSecs + 600,
          'gameData': const [],
          'BRScoreChange': rp,
          'BRScore': cum,
          'map': 'olympus_rotation',
        });

    Future<RankedHistoryStore> storeWith(List<RankedMatch> matches) async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.upsertAll('1', matches);
      return store;
    }

    test('sums RP over an unbroken chain', () async {
      final store = await storeWith([
        chained(100, rp: 50, cum: 1000), // anchor, before the window
        chained(2000, rp: 205, cum: 1205),
        chained(3000, rp: -13, cum: 1192),
      ]);
      expect(
        await store.netRpInWindow('1', windowStart, windowEnd, currentRp: 1192),
        192,
      );
    });

    test('counts only RP earned after a rank reset', () async {
      final store = await storeWith([
        chained(100, rp: 50, cum: 12085), // anchor: end of the previous split
        chained(2000, rp: 0, cum: 12085),
        chained(2500, rp: 0, cum: 4420), // ← reset
        chained(3000, rp: 205, cum: 4625),
        chained(3500, rp: -13, cum: 4612),
      ]);
      expect(
        await store.netRpInWindow('1', windowStart, windowEnd, currentRp: 4612),
        192,
      );
    });

    test(
      'returns null when history does not reach back to the start',
      () async {
        final store = await storeWith([chained(2000, rp: 205, cum: 1205)]);
        expect(
          await store.netRpInWindow(
            '1',
            windowStart,
            windowEnd,
            currentRp: 1205,
          ),
          isNull,
        );
      },
    );

    test('returns null when the chain is broken mid-window', () async {
      final store = await storeWith([
        chained(100, rp: 50, cum: 1000),
        chained(2000, rp: 205, cum: 1205),
        // A gap: the running total jumped by more than this row's rp_change.
        chained(3000, rp: 20, cum: 1600),
      ]);
      expect(
        await store.netRpInWindow('1', windowStart, windowEnd, currentRp: 1600),
        isNull,
      );
    });

    test('returns null when the newest row is behind the live RP', () async {
      final store = await storeWith([
        chained(100, rp: 50, cum: 6000),
        chained(2000, rp: 315, cum: 6315),
      ]);
      expect(
        await store.netRpInWindow('1', windowStart, windowEnd, currentRp: 6758),
        isNull,
      );
    });

    test('returns null for a uid with no history at all', () async {
      final store = await storeWith([chained(100, rp: 50, cum: 1000)]);
      expect(
        await store.netRpInWindow(
          'nobody',
          windowStart,
          windowEnd,
          currentRp: 1000,
        ),
        isNull,
      );
    });

    test('an empty window with an intact chain is a provable zero', () async {
      // Current RP still equals the anchor's total - nothing was played, so
      // this is a provable 0, not "can't determine".
      final store = await storeWith([chained(100, rp: 50, cum: 1000)]);
      expect(
        await store.netRpInWindow('1', windowStart, windowEnd, currentRp: 1000),
        0,
      );
    });

    test(
      'an empty window still returns null when RP has moved since',
      () async {
        // Same shape, but current RP has drifted from the anchor - so matches
        // were played that local history never saw. The window is not covered
        // and the answer is genuinely unknown.
        final store = await storeWith([chained(100, rp: 50, cum: 1000)]);
        expect(
          await store.netRpInWindow(
            '1',
            windowStart,
            windowEnd,
            currentRp: 1240,
          ),
          isNull,
        );
      },
    );

    test('counts pubs as chain links without adding RP', () async {
      final store = await storeWith([
        chained(100, rp: 50, cum: 1000),
        chained(2000, rp: 205, cum: 1205),
        chained(2500, rp: 0, cum: 1205), // pubs — no RP movement
        chained(3000, rp: -13, cum: 1192),
      ]);
      expect(
        await store.netRpInWindow('1', windowStart, windowEnd, currentRp: 1192),
        192,
      );
    });

    test('is scoped to the requested uid', () async {
      final store = await storeWith([
        chained(100, rp: 50, cum: 1000),
        chained(2000, rp: 205, cum: 1205),
      ]);
      await store.upsertAll('2', [match('2', 2000, rp: 999)]);
      expect(
        await store.netRpInWindow('1', windowStart, windowEnd, currentRp: 1205),
        205,
      );
    });
  });

  group('SQL aggregation parity with the Dart aggregates', () {
    // Covers the F2 gap: values in (-1000, -250) disagreed between SQL and
    // Dart because kMinPlausibleRpChange only reached one of them.
    test(
      'net RP, wins and losses agree with Dart at every RP boundary',
      () async {
        const boundaries = [
          -1500,
          -1001,
          -1000,
          -999,
          -500,
          -251,
          -250,
          -249,
          -1,
          1,
          998,
          999,
          1000,
          1001,
          1500,
        ];
        for (final rp in boundaries) {
          final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
          final m = match('1', 1000, rp: rp);
          await store.upsertAll('1', [m]);

          final sql = await store.summaryFor('1');
          final dart = summarize(rankedOnly([m]));

          expect(sql.games, dart.games, reason: 'games at rp=$rp');
          expect(sql.netRp, dart.netRp, reason: 'netRp at rp=$rp');
          expect(sql.wins, dart.wins, reason: 'wins at rp=$rp');
          expect(sql.losses, dart.losses, reason: 'losses at rp=$rp');
          await store.close();
        }
      },
    );

    test('the plausible RP range is -250 ..= 999 inclusive', () async {
      // Pins the boundary itself, so a future tuning of either constant has to
      // be a deliberate edit here rather than a silent behaviour change.
      expect(isImplausibleRpChange(-251), isTrue);
      expect(isImplausibleRpChange(-250), isFalse);
      expect(isImplausibleRpChange(999), isFalse);
      expect(isImplausibleRpChange(1000), isTrue);
      expect(effectiveRpOf(-400), 0);
      expect(effectiveRpOf(-250), -250);
      expect(effectiveRpOf(1000), 0);
    });

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

      final sqlLegendMap = await store.legendMapBreakdownsFor('1');
      final dartLegendMap = {
        for (final c in legendMapBreakdowns(ranked)) (c.legend, c.mapName): c,
      };
      expect(sqlLegendMap.length, dartLegendMap.length);
      for (final s in sqlLegendMap) {
        final d = dartLegendMap[(s.legend, s.mapName)]!;
        expect(s.games, d.games);
        expect(s.totalRp, d.totalRp);
        expect(s.wins, d.wins);
        expect(s.losses, d.losses);
      }
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

    test('mapBreakdownsFor merges map-key spelling variants, and matchesForMap '
        'resolves every variant behind the merged row', () async {
      // 'edistrict' and 'edistrict_rotation' both name E-District (see
      // kBattleRoyaleMaps) - grouping on the raw key would render two
      // identically-labelled rows instead of one merged row, and a
      // drill-down keyed to just one raw spelling would miss the matches
      // recorded under the other.
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.upsertAll('1', [
        match('1', 0, mapKey: 'edistrict', rp: 20),
        match('1', 700, mapKey: 'edistrict_rotation', rp: 30),
      ]);

      final maps = await store.mapBreakdownsFor('1');
      expect(maps.length, 1);
      expect(maps.single.displayName, 'E-District');
      expect(maps.single.games, 2);
      expect(maps.single.totalRp, 50);

      final drillDown = await store.matchesForMap('1', maps.single.mapKey);
      expect(drillDown.length, 2);
    });

    test(
      'legendBreakdownsFor merges legend-name case variants, and '
      'matchesForLegend resolves every variant behind the merged row',
      () async {
        // A raw "axle" vs "Axle" for the same player must not split one
        // legend into two identically-labelled rows — same reasoning as the
        // map-key merge above.
        final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
        addTearDown(store.close);
        await store.upsertAll('1', [
          match('1', 0, legend: 'axle', rp: 20),
          match('1', 700, legend: 'Axle', rp: 30),
        ]);

        final legends = await store.legendBreakdownsFor('1');
        expect(legends.length, 1);
        expect(legends.single.legend, 'Axle');
        expect(legends.single.games, 2);
        expect(legends.single.totalRp, 50);

        final drillDown = await store.matchesForLegend(
          '1',
          legends.single.legend,
        );
        expect(drillDown.length, 2);
      },
    );

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

    test(
      'dayOfWeekBucketsFor (lifetime and per-split) matches the Dart path',
      () async {
        final store = await seeded();
        addTearDown(store.close);

        final allRanked = rankedOnly(await store.getAll('1'));
        final sqlLifetime = await store.dayOfWeekBucketsFor('1');
        final dartLifetime = dayOfWeekBuckets(allRanked);
        expect(
          sqlLifetime.map((b) => (b.weekday, b.games, b.netRp)).toList(),
          dartLifetime.map((b) => (b.weekday, b.games, b.netRp)).toList(),
        );

        final s1Ranked = rankedOnly(
          await store.getBySeason('1', 'br_ranked_s1_s1'),
        );
        final sqlSplit = await store.dayOfWeekBucketsFor(
          '1',
          seasonId: 'br_ranked_s1_s1',
        );
        final dartSplit = dayOfWeekBuckets(s1Ranked);
        expect(
          sqlSplit.map((b) => (b.weekday, b.games, b.netRp)).toList(),
          dartSplit.map((b) => (b.weekday, b.games, b.netRp)).toList(),
        );
      },
    );

    test(
      'squadBreakdownFor splits ranked games by full vs partial squad',
      () async {
        final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
        addTearDown(store.close);
        await store.upsertAll('1', [
          match('1', 100, rp: 40, isPartyFull: true),
          match('1', 200, rp: -20, isPartyFull: true),
          match('1', 300, rp: 60, isPartyFull: false),
          match('1', 250, rp: 0, isPartyFull: false), // pub, excluded
        ]);

        final split = await store.squadBreakdownFor('1');
        expect(split.full.games, 2);
        expect(split.full.netRp, 20);
        expect(split.partial.games, 1, reason: 'the 0-RP pub is not ranked');
        expect(split.partial.netRp, 60);
      },
    );

    test(
      'squadBreakdownFor returns empty summaries for an untouched scope',
      () async {
        final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
        addTearDown(store.close);
        final split = await store.squadBreakdownFor('nobody');
        expect(split.full.games, 0);
        expect(split.partial.games, 0);
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

    test('the season-id backfill uses its index', () async {
      final store = RankedHistoryStore(overridePath: dbPath);
      await store.upsertAll('1', [match('1', 100), match('1', 200)]);
      await store
          .close(); // flush schema + rows to the file for a 2nd connection

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

  group('personalBestGamesFor', () {
    /// A match carrying only the trackers it's given. Omitting one is the
    /// "upstream reported no tracker" shape that makes the column NULL -
    /// what a player who hasn't equipped BR Kills/BR Damage actually produces.
    RankedMatch tracked(
      String uid,
      int startSecs, {
      int? kills,
      int? damage,
      int rp = 10,
    }) => RankedMatch.fromJson({
      'uid': uid,
      'name': 'Tester',
      'legendPlayed': 'Axle',
      'gameMode': 'BATTLE_ROYALE',
      'gameLengthSecs': 600,
      'gameStartTimestamp': startSecs,
      'gameEndTimestamp': startSecs + 600,
      'gameData': [
        if (kills != null) {'key': 'kills', 'value': kills, 'name': 'BR Kills'},
        if (damage != null)
          {'key': 'damage', 'value': damage, 'name': 'BR Damage'},
      ],
      'BRScoreChange': rp,
      'BRScore': 1000,
      'map': 'olympus_rotation',
      'isPartyFull': false,
    });

    test('reports no best game when no row ever carried the tracker', () async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.upsertAll('1', [tracked('1', 100), tracked('1', 200)]);

      final best = await store.personalBestGamesFor('1');

      // `ORDER BY ... LIMIT 1` always returns a row from a non-empty table, so
      // without an IS NOT NULL filter these came back as real matches whose
      // stat is null - and the Personal Best UI reads the stat, not the match.
      expect(best.bestKillsGame, isNull);
      expect(best.bestDamageGame, isNull);
      // RP is never null, so this one still resolves.
      expect(best.bestRpGame, isNotNull);
    });

    test('ignores unreported games when picking the best', () async {
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.upsertAll('1', [
        tracked('1', 100), // no trackers at all
        tracked('1', 200, kills: 4, damage: 1200),
        tracked('1', 300, kills: 1, damage: 300),
      ]);

      final best = await store.personalBestGamesFor('1');

      expect(best.bestKillsGame?.kills, 4);
      expect(best.bestDamageGame?.damage, 1200);
    });

    test(
      'a reported zero is a real scoreless game, not "unreported"',
      () async {
        final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
        addTearDown(store.close);
        await store.upsertAll('1', [tracked('1', 100, kills: 0, damage: 0)]);

        final best = await store.personalBestGamesFor('1');

        expect(best.bestKillsGame?.kills, 0);
        expect(best.bestDamageGame?.damage, 0);
      },
    );
  });

  group('opening is not a check-then-act race', () {
    test('concurrent first access opens the database exactly once', () async {
      final dir = Directory.systemTemp.createTempSync('rhs_open');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = RankedHistoryStore(
        overridePath: p.join(dir.path, 'ranked.db'),
      );
      addTearDown(store.close);

      // Mirrors how ranked providers resume in the same microtask drain and
      // race into _open - before it memoized the future, each started its
      // own openDatabase.
      await Future.wait([
        store.count('1'),
        store.rankedSeasonCounts('1'),
        store.seasonCounts('1'),
        store.summaryFor('1'),
        store.personalBestGamesFor('1'),
      ]);

      expect(store.openCount, 1);
      // And the connection it kept is live.
      await store.upsertAll('1', [match('1', 100)]);
      expect(await store.count('1'), 1);
    });

    test('a later call reuses the open database', () async {
      final dir = Directory.systemTemp.createTempSync('rhs_open2');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = RankedHistoryStore(
        overridePath: p.join(dir.path, 'ranked.db'),
      );
      addTearDown(store.close);

      await store.count('1');
      await store.count('1');
      await store.summaryFor('1');

      // The memoized future is cleared on completion, so the fast path has to
      // be the _db field - not a permanently-retained future.
      expect(store.openCount, 1);
    });
  });
}
