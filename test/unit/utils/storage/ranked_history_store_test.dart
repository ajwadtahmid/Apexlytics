import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';

void main() {
  // sqflite has no native binding under `flutter test` (host VM) — use FFI.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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
}
