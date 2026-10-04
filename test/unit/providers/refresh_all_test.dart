import 'dart:async';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/refresh_all_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/services/games_service.dart';
import 'package:apexlytics/services/player_service.dart';
import 'package:apexlytics/utils/error_messages.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:apexlytics/utils/storage/legend_stats_storage.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';
import 'package:apexlytics/utils/storage/rp_snapshot_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers.dart';

class MockGamesService extends Mock implements GamesService {}

Map<String, Object?> playerJson(String name, String uid, int rp) => {
  'global': {
    'name': name,
    'uid': uid,
    'platform': 'PC',
    'level': 10,
    'rank': {'rankName': 'Gold', 'rankScore': rp},
  },
  'legends': {
    'selected': {'LegendName': 'Wraith', 'data': []},
    'all': {
      'Wraith': {
        'data': [
          {'key': 'kills', 'name': 'Kills', 'value': 100},
        ],
      },
    },
  },
};

RankedMatch match(String uid, int start) => RankedMatch.fromJson({
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

const a = PlayerProfile(name: 'Alpha', uid: '1000000001', platform: 'PC');
const b = PlayerProfile(name: 'Bravo', uid: '1000000002', platform: 'PC');
const c = PlayerProfile(name: 'Charlie', uid: '1000000003', platform: 'PC');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  var dbCounter = 0;
  late RankedHistoryStore store;
  late SharedPreferences prefs;
  late MockGamesService games;
  late FakeHttpAdapter adapter;
  late PlayerService players;
  // uid → what /player/uid answers; absent = 404.
  late Map<String, Object?> statsByUid;
  // While true the transport fails outright, as when the phone is offline.
  late bool offline;

  Future<void> setUpWorld({Map<String, Object> prefsInit = const {}}) async {
    SharedPreferences.setMockInitialValues(prefsInit);
    prefs = await SharedPreferences.getInstance();
    // The snapshot cache is process-wide; reset it so tests don't dedupe each other's readings.
    resetSnapshotCache();
    offline = false;
    store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);
    games = MockGamesService();
    statsByUid = {
      a.uid: playerJson('Alpha', a.uid, 5000),
      b.uid: playerJson('Bravo', b.uid, 6000),
      c.uid: playerJson('Charlie', c.uid, 7000),
    };
    adapter = FakeHttpAdapter({
      '/player/uid': (RequestOptions o) {
        if (offline) {
          throw DioException.connectionError(
            requestOptions: o,
            reason: 'offline',
          );
        }
        return statsByUid[o.queryParameters['uid']] ??
            const FakeReply(404, {'error': 'Player not found'});
      },
    });
    players = PlayerService(
      ApiService(
        ApiCacheStore(
          overridePath:
              'file:refresh_all_${dbCounter++}?mode=memory&cache=shared',
        ),
        httpClientAdapter: adapter,
      ),
    );
    for (final p in [a, b, c]) {
      when(() => games.getMatches(p.uid)).thenAnswer(
        (_) async => GamesMatches([match(p.uid, 1000), match(p.uid, 2000)]),
      );
    }
  }

  Future<RefreshAllReport> run(
    List<PlayerProfile> profiles, {
    void Function(int, int)? onProgress,
  }) => refreshProfiles(
    profiles: profiles,
    players: players,
    games: games,
    store: store,
    prefs: prefs,
    onProgress: onProgress,
  );

  group('refreshProfiles', () {
    test('records stats, RP graph, legend stats and history for each profile, '
        'in order', () async {
      await setUpWorld();
      final progress = <(int, int)>[];

      final report = await run([a, b], onProgress: (d, t) => progress.add((d, t)));

      expect(report.results.map((r) => r.profile.name), ['Alpha', 'Bravo']);
      expect(report.results.every((r) => r.statsOk), isTrue);
      expect(
        report.results.map((r) => r.history),
        everyElement(RankedSyncOutcome.synced),
      );
      expect(report.results.map((r) => r.newMatches), [2, 2]);
      expect(report.newMatches, 4);
      expect(report.hasProblems, isFalse);
      expect(report.aborted, isFalse);
      expect(progress, [(1, 2), (2, 2)]);

      // RP graph
      expect((await store.snapshotsFor(a.uid)).single.rp, 5000);
      expect((await store.snapshotsFor(b.uid)).single.rp, 6000);
      // Legend stats, kept per UID
      expect(loadLegendStats(prefs, uid: a.uid).single.name, 'Wraith');
      expect(loadLegendStats(prefs, uid: b.uid).single.name, 'Wraith');
      // History
      expect(await store.count(a.uid), 2);
      expect(await store.count(b.uid), 2);
      // Stats first, then history, per profile.
      verifyInOrder([() => games.getMatches(a.uid), () => games.getMatches(b.uid)]);
    });

    test('a profile whose stats fail still gets its history, and the rest '
        'carry on', () async {
      await setUpWorld();
      statsByUid.remove(b.uid); // 404

      final report = await run([a, b, c]);

      final byName = {for (final r in report.results) r.profile.name: r};
      expect(byName['Alpha']!.statsOk, isTrue);
      expect(byName['Bravo']!.statsOk, isFalse);
      expect(byName['Bravo']!.history, RankedSyncOutcome.synced);
      expect(byName['Bravo']!.newMatches, 2);
      expect(byName['Charlie']!.statsOk, isTrue);
      expect(report.hasProblems, isTrue);
      expect(await store.snapshotsFor(b.uid), isEmpty);
    });

    test('a failed history call is reported, and the rest carry on', () async {
      await setUpWorld();
      when(() => games.getMatches(a.uid)).thenThrow(const AppException('down'));

      final report = await run([a, b]);

      expect(report.results.first.history, isNull);
      expect(report.results.first.statsOk, isTrue);
      expect(report.results.first.hasProblem, isTrue);
      expect(report.results.first.historySummary, "Couldn't fetch history");
      expect(report.results.last.history, RankedSyncOutcome.synced);
    });

    test('force goes past a cooldown that would otherwise skip /games', () async {
      await setUpWorld(
        prefsInit: {
          PrefsKeys.gamesNextSync(a.uid): DateTime.now()
              .add(const Duration(hours: 2))
              .millisecondsSinceEpoch,
          PrefsKeys.gamesLastOutcome(a.uid): RankedSyncOutcome.synced.name,
        },
      );

      final report = await run([a]);

      verify(() => games.getMatches(a.uid)).called(1);
      expect(report.results.single.newMatches, 2);
      // The next normal sync replays this outcome instead of asking again.
      final next = prefs.getInt(PrefsKeys.gamesNextSync(a.uid))!;
      expect(next, greaterThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('server decisions that aren\'t errors come through as such', () async {
      await setUpWorld();
      when(() => games.getMatches(a.uid)).thenAnswer(
        (_) async => const GamesPending(
          status: 'not_tracked',
          retryAfter: Duration(minutes: 5),
        ),
      );
      when(() => games.getMatches(b.uid)).thenAnswer(
        (_) async => const GamesPending(
          status: 'queued',
          retryAfter: Duration(minutes: 5),
        ),
      );

      final report = await run([a, b]);

      expect(report.results[0].history, RankedSyncOutcome.notTracked);
      expect(report.results[0].historySummary, contains('Not tracked'));
      expect(report.results[1].history, RankedSyncOutcome.queued);
      expect(report.results[1].historySummary, contains('queued'));
      expect(report.results.every((r) => r.statsOk), isTrue);
      expect(report.hasProblems, isTrue);
    });

    test('only new matches are counted on a second run', () async {
      await setUpWorld();
      await run([a]);

      final second = await run([a]);

      expect(second.results.single.newMatches, 0);
      expect(second.results.single.historySummary, 'History up to date');
      expect(await store.count(a.uid), 2);
    });

    test('an old cached copy of the stats is not recorded as a new reading', () async {
      await setUpWorld();
      await run([a]); // fills the stats cache
      await store.deleteAll(); // start the readings over
      resetSnapshotCache();
      offline = true; // the network drops; only the cached copy can answer

      final report = await run([a]);

      expect(report.results.single.statsOk, isFalse);
      expect(await store.snapshotsFor(a.uid), isEmpty);
    });

    test('"Clear all data" mid-run stops it and writes nothing more', () async {
      await setUpWorld();
      when(() => games.getMatches(a.uid)).thenAnswer((_) async {
        await store.deleteAll(); // the user erased everything meanwhile
        return GamesMatches([match(a.uid, 1000)]);
      });

      final report = await run([a, b, c]);

      expect(report.aborted, isTrue);
      expect(await store.count(a.uid), 0);
      verifyNever(() => games.getMatches(b.uid));
      expect(
        adapter.requests.map((r) => r.queryParameters['uid']),
        isNot(contains(b.uid)),
      );
    });
  });

  group('RefreshAllNotifier', () {
    Future<ProviderContainer> containerFor({
      required bool owner,
      List<PlayerProfile> profiles = const [a, b, c],
      int active = 0,
    }) async {
      await setUpWorld(
        prefsInit: {
          if (owner) PrefsKeys.ownerUnlocked: true,
          PrefsKeys.profiles:
              '[${profiles.map((p) => '{"name":"${p.name}","uid":"${p.uid}","platform":"PC"}').join(',')}]',
          PrefsKeys.activeProfileIndex: active,
        },
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          rankedHistoryStoreProvider.overrideWithValue(store),
          gamesServiceProvider.overrideWithValue(games),
          playerServiceProvider.overrideWithValue(players),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('does nothing on a device that is not unlocked as the owner', () async {
      final container = await containerFor(owner: false);

      final report = await container.read(refreshAllProvider.notifier).run();

      expect(report, isNull);
      verifyNever(() => games.getMatches(any()));
    });

    test('refreshes the active profile first, then the rest in order', () async {
      final container = await containerFor(owner: true, active: 1);

      final report = await container.read(refreshAllProvider.notifier).run();

      expect(report!.results.map((r) => r.profile.name), [
        'Bravo',
        'Alpha',
        'Charlie',
      ]);
    });

    test('reports running while it works, and ignores a second press', () async {
      final container = await containerFor(owner: true);
      final gate = Completer<GamesResult>();
      when(() => games.getMatches(a.uid)).thenAnswer((_) => gate.future);
      final notifier = container.read(refreshAllProvider.notifier);

      final first = notifier.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(refreshAllProvider).running, isTrue);
      expect(container.read(refreshAllProvider).total, 3);

      expect(await notifier.run(), isNull, reason: 'already running');

      gate.complete(GamesMatches([match(a.uid, 1000)]));
      await first;
      expect(container.read(refreshAllProvider).running, isFalse);
    });

    test('nobody saved means nothing to do', () async {
      final container = await containerFor(owner: true, profiles: const []);

      expect(await container.read(refreshAllProvider.notifier).run(), isNull);
    });
  });
}
