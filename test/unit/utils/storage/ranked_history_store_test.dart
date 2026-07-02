import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/utils/formatting/season_utils.dart';
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

  RankedMatch match(String uid, int startSecs, {String legend = 'Axle'}) =>
      RankedMatch.fromJson({
        'uid': uid,
        'name': 'Tester',
        'legendPlayed': legend,
        'gameMode': 'BATTLE_ROYALE',
        'gameLengthSecs': 600,
        'gameStartTimestamp': startSecs,
        'gameEndTimestamp': startSecs + 600,
        'gameData': [
          {'key': 'kills', 'value': 3, 'name': 'BR Kills'},
        ],
        'BRScoreChange': 10,
        'BRScore': 1000,
        'map': 'olympus_rotation',
      });

  test('persists matches and returns them newest first', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    await store.upsertAll('1', [match('1', 100), match('1', 300), match('1', 200)]);

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

  test('export rows import into a fresh store (single-file migration)', () async {
    final source = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    await source.upsertAll('1', [match('1', 100, legend: 'Wraith'), match('1', 200)]);
    final rows = await source.exportRows();
    await source.close();

    final restored = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(restored.close);
    await restored.importRows(rows);

    final all = await restored.getAll('1');
    expect(all.length, 2);
    expect(all.any((m) => m.legend == 'Wraith'), true);
  });

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

  test('matches outside every known season are stamped Other', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    await store.upsertAll(
      '1',
      [match('1', 5000)], // end 5_600_000ms, outside the season below
      seasons: {'s1': season('br_ranked_s1_s1', 0, 1000)},
    );

    expect((await store.seasonCounts('1'))[kOtherSeasonId], 1);
  });

  test('backfillSeasonIds classifies rows written without season metadata',
      () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    // No seasons passed → season_id left NULL (omitted from seasonCounts).
    await store.upsertAll('1', [match('1', 100), match('1', 300)]);
    expect(await store.seasonCounts('1'), isEmpty);

    await store.backfillSeasonIds({'s1': season('br_ranked_s1_s1', 0, 1000)});
    expect((await store.seasonCounts('1'))['br_ranked_s1_s1'], 2);
  });

  test('backfillSeasonIds reclassifies rows previously stamped Other once '
      'their season becomes known', () async {
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);

    // Written before the split's window was cached → stamped Other.
    await store.upsertAll(
      '1',
      [match('1', 500)], // end 1_100_000ms
      seasons: {'other': season('br_ranked_other', 0, 100)},
    );
    expect((await store.seasonCounts('1'))[kOtherSeasonId], 1);

    // The split's window is now known → backfill should self-correct it.
    await store.backfillSeasonIds({'s1': season('br_ranked_s1_s1', 0, 2000)});
    final counts = await store.seasonCounts('1');
    expect(counts['br_ranked_s1_s1'], 1);
    expect(counts[kOtherSeasonId], isNull);
  });

  test('migrates a v1 database by adding season_id (rows preserved, NULL)',
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
    expect(await store.seasonCounts('1'), isEmpty); // season_id NULL until backfill

    await store.backfillSeasonIds({'s1': season('br_ranked_s1_s1', 0, 1000)});
    expect((await store.seasonCounts('1'))['br_ranked_s1_s1'], 1);
  });
}
