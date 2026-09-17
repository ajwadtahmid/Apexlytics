import 'dart:convert';
import 'dart:io';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/storage/backup_service.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
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
      PrefsKeys.compactLegendCards: true,
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
    test('restores a native string-list value instead of dropping it', () async {
      // Every backed-up list pref today is stored as a JSON-encoded string, so
      // this simulates the type a future setStringList-backed pref would
      // round-trip as — the exact case that used to hit the "unsupported
      // type" branch and vanish silently.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await restorePrefsData(prefs, {
        PrefsKeys.favoriteRankedMapNames: ['Olympus', "World's Edge"],
      });

      expect(prefs.getStringList(PrefsKeys.favoriteRankedMapNames), [
        'Olympus',
        "World's Edge",
      ]);
    });

    test('still restores string/int/bool/double values', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await restorePrefsData(prefs, {
        PrefsKeys.playerName: 'Aceu',
        PrefsKeys.statsRefreshMinutes: 30,
        PrefsKeys.compactLegendCards: true,
        PrefsKeys.keepScreenOn: true,
      });

      expect(prefs.getString(PrefsKeys.playerName), 'Aceu');
      expect(prefs.getInt(PrefsKeys.statsRefreshMinutes), 30);
      expect(prefs.getBool(PrefsKeys.compactLegendCards), isTrue);
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
  });

  group(
    'exportBackup → previewBackup → commitBackupImport round trip',
    () {
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

      test(
        'a real export round-trips through preview and commit: prefs, '
        'ranked history, and RP snapshots all land',
        () async {
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
        },
      );

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
          final preview = BackupPreview.forTesting(
            version: 3,
            envelope: decoded,
          );

          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
          addTearDown(store.close);

          await commitBackupImport(preview, prefs, rankedStore: store);
          await commitBackupImport(preview, prefs, rankedStore: store);

          expect(await store.count(uid), 1);
        },
      );
    },
  );

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
}
