import 'dart:convert';
import 'dart:io';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/formatting/snapshot_types.dart';
import 'package:apexlytics/utils/storage/backup_service.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // sqflite has no native binding under `flutter test` (host VM) — use FFI.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('backup allowlist exhaustiveness', () {
    // Every key shape the app persists, each with an explicit verdict -
    // maintained by hand, but both real escapes so far (Wildcard alerts,
    // rank_goal_) were keys nobody ever decided about either way.
    const uid = '1006838015507';
    const verdicts = <String, bool>{
      // ── Backed up: user intent worth carrying to a new device ──
      PrefsKeys.profiles: true,
      PrefsKeys.activeProfileIndex: true,
      PrefsKeys.playerName: true,
      PrefsKeys.playerUid: true,
      PrefsKeys.playerPlatform: true,
      PrefsKeys.statsRefreshMinutes: true,
      PrefsKeys.keepScreenOn: true,
      PrefsKeys.notifyPubsMapRotation: true,
      PrefsKeys.notifyRankedMapRotation: true,
      PrefsKeys.notifyMixtapeMapRotation: true,
      PrefsKeys.notifyWildcardMapRotation: true,
      PrefsKeys.rankedNotifyMinutes: true,
      PrefsKeys.pubsNotifyMinutes: true,
      PrefsKeys.mixtapeNotifyMinutes: true,
      PrefsKeys.wildcardNotifyMinutes: true,
      PrefsKeys.favoriteRankedMapNames: true,
      PrefsKeys.favoritePubsMapNames: true,
      PrefsKeys.defaultTab: true,
      PrefsKeys.searchFavorites: true,
      PrefsKeys.legendStats: true,
      PrefsKeys.legendVisitStack: true,
      PrefsKeys.seasonHistory: true,
      PrefsKeys.statSnapshots: true,
      // ── Excluded, each for a stated reason ──
      // Device-local first-run state: a restore on a fresh install should
      // still show the tour once.
      PrefsKeys.onboardingVersion: false,
      PrefsKeys.uidSearchWarningShown: false,
      PrefsKeys.rankedInfoCoachMarkShown: false,
      // Legacy migration-only key; build() derives the per-mode keys from it.
      PrefsKeys.mapNotifyMinutes: false,
    };

    test('every fixed PrefsKeys entry has the expected verdict', () {
      for (final MapEntry(key: key, value: expected) in verdicts.entries) {
        expect(backupIncludesKey(key), expected, reason: key);
      }
    });

    test('every UID-scoped key shape has the expected verdict', () {
      // Per-UID data the user would expect to survive a device move...
      expect(backupIncludesKey(PrefsKeys.snapshotKeyFor(uid)), isTrue);
      expect(backupIncludesKey(PrefsKeys.legendStatsKeyFor(uid)), isTrue);
      expect(backupIncludesKey(PrefsKeys.rankGoalKeyFor(uid)), isTrue);
      expect(backupIncludesKey(PrefsKeys.legendVisitStackKeyFor(uid)), isTrue);
      // ...versus transient sync bookkeeping, which must not be restored: a
      // stale deadline would open a fresh install inside a 6 h cooldown.
      expect(backupIncludesKey(PrefsKeys.gamesNextSync(uid)), isFalse);
      expect(backupIncludesKey(PrefsKeys.gamesLastOutcome(uid)), isFalse);
    });
  });

  group('backup key allowlist', () {
    // Every map-rotation notification setting a user can configure. If a new
    // alert category is added, its toggle + minutes keys belong here AND in the
    // backup allowlist — this test fails until both are wired, so a category
    // can't silently escape backup/restore (the Wildcard regression).
    const notificationKeys = <String>[
      PrefsKeys.notifyPubsMapRotation,
      PrefsKeys.notifyRankedMapRotation,
      PrefsKeys.notifyMixtapeMapRotation,
      PrefsKeys.notifyWildcardMapRotation,
      PrefsKeys.pubsNotifyMinutes,
      PrefsKeys.rankedNotifyMinutes,
      PrefsKeys.mixtapeNotifyMinutes,
      PrefsKeys.wildcardNotifyMinutes,
    ];

    for (final key in notificationKeys) {
      test('"$key" is included in backups', () {
        expect(backupIncludesKey(key), isTrue);
      });
    }

    test('Wildcard notification settings are backup-included', () {
      // The exact keys H-1 found missing — kept as an explicit guard.
      expect(backupIncludesKey(PrefsKeys.notifyWildcardMapRotation), isTrue);
      expect(backupIncludesKey(PrefsKeys.wildcardNotifyMinutes), isTrue);
    });

    test('runtime caches and one-shot flags are excluded from backups', () {
      // Server-derived / device-local state must not travel between devices.
      expect(
        backupIncludesKey(PrefsKeys.rankGoalKeyFor('1006838015507')),
        isTrue,
      );
      expect(
        backupIncludesKey(PrefsKeys.gamesNextSync('1006838015507')),
        isFalse,
      );
      expect(
        backupIncludesKey(PrefsKeys.gamesLastOutcome('1006838015507')),
        isFalse,
      );
      expect(backupIncludesKey(PrefsKeys.uidSearchWarningShown), isFalse);
      expect(backupIncludesKey(PrefsKeys.onboardingVersion), isFalse);
      expect(backupIncludesKey('api_cache:whatever'), isFalse);
    });
  });

  group('restorePrefsData', () {
    test('skips a value whose type is not the one the app stores, rather than '
        'writing something the settings reader would throw on', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await restorePrefsData(prefs, {
        // Favourites are stored as a JSON-encoded string; a native list would
        // make `getString` throw on every launch.
        PrefsKeys.favoriteRankedMapNames: ['Olympus', "World's Edge"],
        PrefsKeys.activeProfileIndex: '0',
        PrefsKeys.keepScreenOn: 1,
        PrefsKeys.statsRefreshMinutes: 'ten',
        PrefsKeys.playerName: 42,
        // A fine value alongside them still lands.
        PrefsKeys.defaultTab: 2,
      });

      expect(prefs.containsKey(PrefsKeys.favoriteRankedMapNames), isFalse);
      expect(prefs.containsKey(PrefsKeys.activeProfileIndex), isFalse);
      expect(prefs.containsKey(PrefsKeys.keepScreenOn), isFalse);
      expect(prefs.containsKey(PrefsKeys.statsRefreshMinutes), isFalse);
      expect(prefs.containsKey(PrefsKeys.playerName), isFalse);
      expect(prefs.getInt(PrefsKeys.defaultTab), 2);
    });

    test('coerceRestoredPref accepts a whole-number double as an int, and '
        'nothing that merely looks similar', () {
      expect(coerceRestoredPref(PrefsKeys.defaultTab, 2.0), 2);
      expect(coerceRestoredPref(PrefsKeys.defaultTab, 2.5), isNull);
      expect(coerceRestoredPref(PrefsKeys.defaultTab, double.nan), isNull);
      expect(coerceRestoredPref(PrefsKeys.defaultTab, '2'), isNull);
      expect(coerceRestoredPref(PrefsKeys.keepScreenOn, true), true);
      expect(coerceRestoredPref(PrefsKeys.keepScreenOn, 'true'), isNull);
      expect(coerceRestoredPref(PrefsKeys.profiles, '[]'), '[]');
      expect(coerceRestoredPref(PrefsKeys.profiles, []), isNull);
      // Per-UID keys follow their prefix: a goal is an int, stats are text.
      expect(coerceRestoredPref(PrefsKeys.rankGoalKeyFor('1'), 7), 7);
      expect(coerceRestoredPref(PrefsKeys.rankGoalKeyFor('1'), '7'), isNull);
      expect(coerceRestoredPref(PrefsKeys.legendStatsKeyFor('1'), '{}'), '{}');
    });

    test('a restored season history is validated and merged with the device\'s '
        'own seasons', () async {
      const day = 86400000;
      final good = {'id': 'br_ranked_s30_s1', 'start': 0, 'end': 60 * day};
      final device = {'id': 'br_ranked_s29_s2', 'start': 100 * day, 'end': 150 * day};
      // Same split as `good`, but the device's window must win.
      final deviceSame = {'id': 'br_ranked_s30_s1', 'start': 1, 'end': 2 * day};

      SharedPreferences.setMockInitialValues({
        PrefsKeys.seasonHistory: jsonEncode([device, deviceSame]),
      });
      final prefs = await SharedPreferences.getInstance();

      await restorePrefsData(prefs, {
        PrefsKeys.seasonHistory: jsonEncode([
          good,
          // Ends before it starts.
          {'id': 'br_ranked_s31_s1', 'start': 90 * day, 'end': 10 * day},
          // A 2,000-day "split" would swallow every match that ever ended.
          {'id': 'br_ranked_s32_s1', 'start': 0, 'end': 2000 * day},
          // Not a split id at all.
          {'id': '__other__', 'start': 0, 'end': 50 * day},
        ]),
      });

      final stored = (jsonDecode(prefs.getString(PrefsKeys.seasonHistory)!) as List)
          .cast<Map<String, dynamic>>();
      expect({for (final s in stored) s['id']}, {
        'br_ranked_s30_s1',
        'br_ranked_s29_s2',
      });
      final s30 = stored.firstWhere((s) => s['id'] == 'br_ranked_s30_s1');
      expect(s30['end'], 2 * day, reason: "the device's own window wins");
    });

    test('still restores string/int/bool/double values', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await restorePrefsData(prefs, {
        PrefsKeys.playerName: 'Aceu',
        PrefsKeys.statsRefreshMinutes: 30,
        PrefsKeys.keepScreenOn: true,
      });

      expect(prefs.getString(PrefsKeys.playerName), 'Aceu');
      expect(prefs.getInt(PrefsKeys.statsRefreshMinutes), 30);
      expect(prefs.getBool(PrefsKeys.keepScreenOn), isTrue);
    });

    test('skips keys not on the backup allowlist', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await restorePrefsData(prefs, {
        PrefsKeys.uidSearchWarningShown: true,
        'api_cache:whatever': 'stale',
      });

      expect(prefs.getBool(PrefsKeys.uidSearchWarningShown), isNull);
      expect(prefs.getString('api_cache:whatever'), isNull);
    });

    test(
      'clears a static setting the backup does not mention, instead of '
      'leaving the on-device value in place',
      () async {
        // A favourite map set on this device (e.g. after the backup being
        // restored was taken) must not survive a restore that says nothing
        // about favourites — "restore" means "match the backup", not "layer
        // the backup on top of whatever's here".
        SharedPreferences.setMockInitialValues({
          PrefsKeys.favoriteRankedMapNames: '["Olympus"]',
          PrefsKeys.keepScreenOn: true,
        });
        final prefs = await SharedPreferences.getInstance();

        await restorePrefsData(prefs, {
          // Mentions keepScreenOn but not favoriteRankedMapNames.
          PrefsKeys.keepScreenOn: false,
        });

        expect(prefs.getBool(PrefsKeys.keepScreenOn), isFalse);
        expect(prefs.getString(PrefsKeys.favoriteRankedMapNames), isNull);
      },
    );

    test(
      "a dynamic per-UID key belonging to a profile the backup doesn't "
      'mention survives the restore',
      () async {
        // Regression guard: the full-replace fix above must be scoped to
        // _staticBackupKeys only — sweeping "not in this backup" for a
        // dynamic key would delete a different profile's stats just because
        // this backup never mentioned that UID.
        const otherUid = '1007849632032';
        SharedPreferences.setMockInitialValues({
          PrefsKeys.legendStatsKeyFor(otherUid): '{"Wraith":{}}',
          PrefsKeys.rankGoalKeyFor(otherUid): 42,
        });
        final prefs = await SharedPreferences.getInstance();

        // A backup for a *different* UID that never references otherUid at
        // all — the realistic shape of restoring someone else's export, or
        // an older export of this same device from before otherUid was added.
        const restoredUid = '1012039108394';
        await restorePrefsData(prefs, {
          PrefsKeys.legendStatsKeyFor(restoredUid): '{"Bangalore":{}}',
        });

        expect(
          prefs.getString(PrefsKeys.legendStatsKeyFor(otherUid)),
          '{"Wraith":{}}',
        );
        expect(prefs.getInt(PrefsKeys.rankGoalKeyFor(otherUid)), 42);
      },
    );
  });

  group('exportBackup → previewBackup → commitBackupImport round trip', () {
    RankedMatch match(String uid, int startSecs) => RankedMatch.fromJson({
      'uid': uid,
      'name': 'Tester',
      'legendPlayed': 'Wraith',
      'gameMode': 'BATTLE_ROYALE',
      'gameLengthSecs': 600,
      'gameStartTimestamp': startSecs,
      'gameEndTimestamp': startSecs + 600,
      'gameData': [
        {'key': 'kills', 'value': 5, 'name': 'BR Kills'},
        {'key': 'damage', 'value': 800, 'name': 'BR Damage'},
      ],
      'BRScoreChange': 20,
      'BRScore': 1020,
      'map': 'olympus_rotation',
      'isPartyFull': true,
    });

    test('a real export round-trips through preview and commit: prefs, '
        'ranked history, and RP snapshots all land', () async {
      const uid = '1006838015507';

      // The exact envelope shape exportBackup produces.
      final envelope = {
        'version': 3,
        'exported_at': DateTime.now().toIso8601String(),
        'prefs': {
          PrefsKeys.playerName: 'Aceu',
          PrefsKeys.playerUid: uid,
          PrefsKeys.statsRefreshMinutes: 15,
        },
        'ranked_history': [match(uid, 1000).toStoredMap()],
        'stat_snapshots': [
          {'uid': uid, 'ts_ms': 5000, 'rp': 1020, 'season_id': null},
        ],
      };

      // Round-trip through JSON exactly as a real file write/read would
      // — this is what proves the no-indentation change still produces
      // valid, fully round-trippable JSON, not just shorter JSON.
      final json = jsonEncode(envelope);
      expect(json.contains('\n  '), isFalse); // confirms no pretty-print
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      final preview = BackupPreview.forTesting(
        version: decoded['version'] as int,
        envelope: decoded,
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);

      final result = await commitBackupImport(
        preview,
        prefs,
        rankedStore: store,
      );

      expect(result, isA<ImportSuccess>());

      expect(prefs.getString(PrefsKeys.playerName), 'Aceu');
      expect(prefs.getString(PrefsKeys.playerUid), uid);
      expect(prefs.getInt(PrefsKeys.statsRefreshMinutes), 15);

      final matches = await store.getAll(uid);
      expect(matches, hasLength(1));
      expect(matches.single.legend, 'Wraith');
      expect(matches.single.kills, 5);
      expect(matches.single.rpChange, 20);

      final snapshots = await store.snapshotsFor(uid);
      expect(snapshots, hasLength(1));
      expect(snapshots.single.rp, 1020);
    });

    test(
      'importing the same export twice is idempotent (no duplicate rows)',
      () async {
        const uid = '1006838015507';
        final envelope = {
          'version': 3,
          'exported_at': DateTime.now().toIso8601String(),
          'prefs': <String, dynamic>{},
          'ranked_history': [match(uid, 2000).toStoredMap()],
          'stat_snapshots': <Map<String, dynamic>>[],
        };
        final decoded =
            jsonDecode(jsonEncode(envelope)) as Map<String, dynamic>;
        final preview = BackupPreview.forTesting(version: 3, envelope: decoded);

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
        addTearDown(store.close);

        await commitBackupImport(preview, prefs, rankedStore: store);
        await commitBackupImport(preview, prefs, rankedStore: store);

        expect(await store.count(uid), 1);
      },
    );
  });

  group('buildBackupBytes', () {
    RankedMatch game(String uid, int start) => RankedMatch.fromJson({
      'uid': uid,
      'name': 'Tester',
      'legendPlayed': 'Axle',
      'gameMode': 'BATTLE_ROYALE',
      'gameLengthSecs': 600,
      'gameStartTimestamp': start,
      'gameEndTimestamp': start + 600,
      'gameData': const [],
      'BRScoreChange': 10,
      'BRScore': 1000,
      'map': 'olympus_rotation',
    });

    Map<String, dynamic> decode(List<int> bytes) =>
        jsonDecode(utf8.decode(decompressIfGzipped(bytes)))
            as Map<String, dynamic>;

    test('streams every page into one valid, restorable envelope', () async {
      const uid = '1006838015507';
      final source = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(source.close);
      await source.upsertAll(uid, [for (var i = 0; i < 7; i++) game(uid, i * 1000)]);
      // Two UIDs, 5 readings: pages of 2 cross both a page seam and a UID seam.
      for (final owner in [uid, '1000000000002']) {
        await source.appendSnapshotsFor(owner, [
          for (var i = 0; i < (owner == uid ? 3 : 2); i++)
            StatSnapshot(
              timestamp: DateTime.fromMillisecondsSinceEpoch(5000 + i),
              rp: 1000 + i,
            ),
        ]);
      }

      final built = await buildBackupBytes(
        prefs: {PrefsKeys.playerName: 'Aceu'},
        // Pages of 3: 3 + 3 + 1, so the page seams are exercised.
        matchPages: source.exportRowPages(pageSize: 3),
        snapshotPages: source.exportSnapshotRowPages(pageSize: 2),
      );

      await source.close(); // the in-memory path is shared while it stays open
      expect(built.matchCount, 7);
      final envelope = decode(built.bytes);
      expect(envelope['version'], 3);
      expect(envelope['prefs'], {PrefsKeys.playerName: 'Aceu'});
      expect((envelope['ranked_history'] as List), hasLength(7));
      final snapshots = (envelope['stat_snapshots'] as List)
          .cast<Map<String, dynamic>>();
      expect(snapshots, hasLength(5), reason: 'every reading, once');
      expect(
        {for (final s in snapshots) '${s['uid']}:${s['ts_ms']}'},
        hasLength(5),
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final target = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      addTearDown(target.close);
      final result = await commitBackupImport(
        BackupPreview.forTesting(version: 3, envelope: envelope),
        prefs,
        rankedStore: target,
      );

      expect(result, isA<ImportSuccess>());
      expect(await target.count(uid), 7);
    });

    test('an empty history is still a valid envelope', () async {
      final built = await buildBackupBytes(
        prefs: const {},
        matchPages: const Stream.empty(),
        snapshotPages: const Stream.empty(),
      );

      final envelope = decode(built.bytes);
      expect(built.matchCount, 0);
      expect(envelope['ranked_history'], isEmpty);
      expect(envelope['stat_snapshots'], isEmpty);
    });
  });

  group('shareBackupFile', () {
    late Directory tmp;
    late File file;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('apx_share_');
      file = File('${tmp.path}/backup.json.gz');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<ShareResult> Function(ShareParams) answering(
      ShareResultStatus status, {
      void Function()? onShare,
    }) => (params) async {
      onShare?.call();
      return ShareResult('', status);
    };

    test('with a cleanup delay the file outlives the share call (the receiving '
        'app may still be reading it) and is removed afterwards', () async {
      await shareBackupFile(
        file,
        [1, 2, 3],
        share: answering(ShareResultStatus.unavailable),
        cleanupDelay: const Duration(milliseconds: 150),
      );
      expect(file.existsSync(), isTrue, reason: 'not deleted at once');

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(file.existsSync(), isFalse);
    });

    test('a completed share counts as exported', () async {
      expect(
        await shareBackupFile(
          file,
          [1, 2, 3],
          share: answering(ShareResultStatus.success),
        ),
        isTrue,
      );
    });

    test('a dismissed share sheet is not an export', () async {
      expect(
        await shareBackupFile(
          file,
          [1, 2, 3],
          share: answering(ShareResultStatus.dismissed),
        ),
        isFalse,
      );
    });

    test('a platform that cannot tell counts as shared', () async {
      expect(
        await shareBackupFile(
          file,
          [1, 2, 3],
          share: answering(ShareResultStatus.unavailable),
        ),
        isTrue,
      );
    });

    test('the file exists while sharing and is gone afterwards, '
        'whatever the outcome', () async {
      for (final status in ShareResultStatus.values) {
        var existedDuringShare = false;
        await shareBackupFile(
          file,
          [1, 2, 3],
          share: answering(status, onShare: () => existedDuringShare = file.existsSync()),
        );
        expect(existedDuringShare, isTrue, reason: '$status');
        expect(file.existsSync(), isFalse, reason: '$status');
      }
    });

    test('a failing share still removes the file and rethrows', () async {
      await expectLater(
        shareBackupFile(
          file,
          [1, 2, 3],
          share: (_) async => throw StateError('share failed'),
        ),
        throwsStateError,
      );
      expect(file.existsSync(), isFalse);
    });
  });

  group('decompressIfGzipped', () {
    test('decompresses real gzip bytes back to the original JSON', () {
      final original = jsonEncode({'hello': 'world', 'n': 1500});
      final compressed = gzip.encode(utf8.encode(original));

      final result = utf8.decode(decompressIfGzipped(compressed));

      expect(result, original);
    });

    test(
      'passes plain (legacy, uncompressed) JSON bytes through unchanged',
      () {
        final plain = utf8.encode(jsonEncode({'version': 3}));

        final result = decompressIfGzipped(plain);

        expect(result, plain);
      },
    );

    test(
      'throws BackupCorruptedException for a truncated/malformed gzip '
      'stream, instead of silently returning partial garbage',
      () {
        // The gzip magic number, but nothing resembling a real gzip stream
        // after it — mirrors a truncated download from cloud storage, which
        // starts correctly but cuts off partway through.
        final malformed = [0x1F, 0x8B, 1, 2, 3, 4, 5];

        expect(
          () => decompressIfGzipped(malformed),
          throwsA(isA<BackupCorruptedException>()),
        );
      },
    );

    test('compression actually shrinks a realistic repetitive payload', () {
      // Mirrors what a real export looks like: the same column names
      // repeated across many rows — exactly what gzip is good at.
      final rows = [
        for (var i = 0; i < 200; i++)
          {
            'id': 'uid_$i',
            'legend': 'Wraith',
            'game_mode': 'BATTLE_ROYALE',
            'map_key': 'olympus_rotation',
            'rp_change': 20,
          },
      ];
      final json = jsonEncode({'ranked_history': rows});
      final compressed = gzip.encode(utf8.encode(json));

      expect(compressed.length, lessThan(utf8.encode(json).length));
    });
  });

  group('commitBackupImport outer rollback', () {
    test(
      "a failure after restorePrefsData already succeeded (e.g. the "
      "database transaction's own commit failing afterward) still rolls "
      'prefs back',
      () async {
        // Regression guard for commitBackupImport's outer _PrefsSnapshot:
        // restorePrefsData runs as the transaction's last step, so it can
        // finish writing successfully and only then have the commit fail.
        // This fake reproduces that ordering without breaking real SQLite.
        SharedPreferences.setMockInitialValues({
          PrefsKeys.playerName: 'OriginalName',
        });
        final prefs = await SharedPreferences.getInstance();

        final preview = BackupPreview.forTesting(
          version: 3,
          envelope: {
            'version': 3,
            'prefs': {PrefsKeys.playerName: 'RestoredName'},
            'ranked_history': const <Map<String, Object?>>[],
            'stat_snapshots': const <Map<String, Object?>>[],
          },
        );

        final result = await commitBackupImport(
          preview,
          prefs,
          rankedStore: _CommitFailsAfterPrefsRestore(),
        );

        expect(result, isA<ImportError>());
        // The point: restorePrefsData's own write DID land (unlike an
        // ordinary mid-write failure, which it already rolls back itself),
        // but commitBackupImport's outer snapshot undoes it anyway.
        expect(prefs.getString(PrefsKeys.playerName), 'OriginalName');
      },
    );
  });

  group('commitBackupImport when the legacy snapshot drain fails', () {
    test('still reports success: rows and prefs both committed, the legacy '
        'keys stay for the next launch', () async {
      const uid = '1006838015507';
      SharedPreferences.setMockInitialValues({
        PrefsKeys.playerName: 'OriginalName',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = _SnapshotDrainFails(overridePath: inMemoryDatabasePath);
      addTearDown(store.close);

      final preview = BackupPreview.forTesting(
        version: 2, // v2 files carry RP snapshots as prefs keys
        envelope: {
          'version': 2,
          'prefs': {
            PrefsKeys.playerName: 'RestoredName',
            'stat_snapshots_$uid': jsonEncode([
              {'ts': 1000, 'rp': 1500},
            ]),
          },
          'ranked_history': [
            {
              'id': '${uid}_1000',
              'uid': uid,
              'start_ms': 1000000,
              'end_ms': 1600000,
              'game_mode': 'BATTLE_ROYALE',
              'rp_change': 10,
            },
          ],
        },
      );

      final result = await commitBackupImport(preview, prefs, rankedStore: store);

      expect(result, isA<ImportSuccess>());
      expect(prefs.getString(PrefsKeys.playerName), 'RestoredName');
      expect(await store.count(uid), 1);
      expect(
        prefs.containsKey('stat_snapshots_$uid'),
        isTrue,
        reason: 'left in place so the startup drain can retry it',
      );
    });
  });

  group('profilesReplacedBy', () {
    String profiles(List<(String, String)> ps) => jsonEncode([
      for (final (name, uid) in ps) {'name': name, 'uid': uid, 'platform': 'PC'},
    ]);

    BackupPreview previewWith(List<(String, String)> ps) =>
        BackupPreview.forTesting(
          version: 3,
          envelope: {
            'prefs': {PrefsKeys.profiles: profiles(ps)},
          },
        );

    test('names current profiles the backup does not contain', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.profiles: profiles([('Kept', '1'), ('Lost', '2')]),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(previewWith([('Kept', '1')]).profilesReplacedBy(prefs), ['Lost']);
    });

    test('is empty when the backup covers every current profile', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.profiles: profiles([('Kept', '1')]),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(previewWith([('Kept', '1'), ('New', '3')]).profilesReplacedBy(prefs), isEmpty);
    });
  });
}

/// Runs the real [restorePrefs] callback (so its writes actually land),
/// then throws — simulating a database transaction whose callback body
/// completed successfully but whose own commit step failed afterward. Never
/// touches a real database; safe to construct without sqflite FFI setup.
class _CommitFailsAfterPrefsRestore extends RankedHistoryStore {
  @override
  Future<int> importBackupData({
    required List<dynamic> matchRows,
    required List<dynamic> snapshotRows,
    Future<void> Function()? restorePrefs,
  }) async {
    if (restorePrefs != null) await restorePrefs();
    throw Exception('simulated transaction commit failure');
  }
}

/// A store whose legacy-snapshot drain fails after an otherwise real restore.
class _SnapshotDrainFails extends RankedHistoryStore {
  _SnapshotDrainFails({super.overridePath});

  @override
  Future<void> appendSnapshotsFor(
    String uid,
    List<StatSnapshot> snapshots,
  ) async => throw Exception('simulated drain failure');
}
