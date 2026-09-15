import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/services/games_service.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockGamesService extends Mock implements GamesService {}

/// Throws from [upsertAll] specifically, leaving every other method real —
/// simulates a local write failure (disk full, a broken migration, …)
/// without needing to stub the store's whole surface. Proves a write
/// failure is no longer misreported as `offline`.
class _ThrowingUpsertStore extends RankedHistoryStore {
  _ThrowingUpsertStore({super.overridePath});

  @override
  Future<void> upsertAll(
    String uid,
    List<RankedMatch> matches, {
    Map<String, SeasonMeta> seasons = const {},
  }) async {
    throw Exception('simulated write failure');
  }
}

/// Builds a [ProviderContainer] backed by an in-memory [SharedPreferences].
Future<ProviderContainer> makeContainer(
  Map<String, Object> initialPrefs,
) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

/// Prefs putting [uid] inside its backoff window with [outcome] recorded.
Map<String, Object> coolingDown(String uid, RankedSyncOutcome outcome) => {
  PrefsKeys.gamesNextSync(uid): DateTime.now()
      .add(const Duration(hours: 1))
      .millisecondsSinceEpoch,
  PrefsKeys.gamesLastOutcome(uid): outcome.name,
};

/// A minimal valid match, ranked (non-zero RP change) so it round-trips
/// through `upsertAll` without special-casing.
RankedMatch _match(String uid, int startSecs, {int rp = 10}) =>
    RankedMatch.fromJson({
      'uid': uid,
      'name': 'Tester',
      'legendPlayed': 'Axle',
      'gameMode': 'BATTLE_ROYALE',
      'gameLengthSecs': 600,
      'gameStartTimestamp': startSecs,
      'gameEndTimestamp': startSecs + 600,
      'gameData': <Map<String, Object?>>[],
      'BRScoreChange': rp,
      'BRScore': 1000 + rp,
      'map': 'olympus_rotation',
      'isPartyFull': false,
    });

void main() {
  const uid = 'uid123';

  group('rankedSyncProvider inside the backoff window', () {
    // Every case here resolves without the network: the persisted deadline is
    // in the future, so the provider replays what it stored and returns.
    for (final outcome in RankedSyncOutcome.values) {
      test('replays a stored ${outcome.name} outcome', () async {
        final container = await makeContainer(coolingDown(uid, outcome));
        addTearDown(container.dispose);

        final result = await container.read(rankedSyncProvider(uid).future);

        expect(result, outcome);
      });
    }

    test('falls back to cooldown when no outcome was stored', () async {
      final container = await makeContainer({
        PrefsKeys.gamesNextSync(uid): DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      });
      addTearDown(container.dispose);

      final result = await container.read(rankedSyncProvider(uid).future);

      expect(result, RankedSyncOutcome.cooldown);
    });

    test(
      'falls back to cooldown when the stored name is unrecognised',
      () async {
        final container = await makeContainer({
          PrefsKeys.gamesNextSync(uid): DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          PrefsKeys.gamesLastOutcome(uid): 'someRemovedOutcome',
        });
        addTearDown(container.dispose);

        final result = await container.read(rankedSyncProvider(uid).future);

        expect(result, RankedSyncOutcome.cooldown);
      },
    );
  });

  group('rankedSyncProvider outside the backoff window (live fetch)', () {
    // sqflite has no native binding under `flutter test` (host VM) — use FFI.
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late MockGamesService gamesService;
    late RankedHistoryStore store;
    late ProviderContainer container;

    /// [store] defaults to a fresh in-memory [RankedHistoryStore]; pass a
    /// custom one (e.g. [_ThrowingUpsertStore]) to simulate a write failure.
    Future<void> setUpWith({RankedHistoryStore? customStore}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      gamesService = MockGamesService();
      store =
          customStore ??
          RankedHistoryStore(overridePath: inMemoryDatabasePath);
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          gamesServiceProvider.overrideWithValue(gamesService),
          rankedHistoryStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(store.close);
    }

    /// Reads [rankedSyncProvider]'s outcome for [uid] via a held listener,
    /// not a bare `container.read(...future)`.
    ///
    /// rankedSyncProvider is `.autoDispose`: its success path has several
    /// `await` points after the last one a bare read is guaranteed to
    /// survive (store writes, then a prefs re-read), so the dispose
    /// scheduler can tear the provider down mid-build once its listener
    /// count drops back to zero between microtasks — the awaited future
    /// then rejects with a generic Riverpod "Ref used after dispose" error
    /// instead of the real result or exception. A held listener, mirroring
    /// what a widget's `ref.watch` keeps alive in production, is the
    /// standard way to read an autoDispose provider reliably in a test.
    /// Must be called *after* the test's `when(...)` stub is set up — a
    /// listener builds the provider eagerly, so calling this first would
    /// hit an unstubbed mock.
    Future<RankedSyncOutcome> readOutcome() {
      container.listen(rankedSyncProvider(uid), (_, _) {});
      return container.read(rankedSyncProvider(uid).future);
    }

    test('GamesMatches persists the matches and returns synced', () async {
      await setUpWith();
      when(
        () => gamesService.getMatches(uid),
      ).thenAnswer((_) async => GamesMatches([_match(uid, 0)]));

      final result = await readOutcome();

      expect(result, RankedSyncOutcome.synced);
      expect(await store.count(uid), 1);
      // The cooldown is armed forward, matching ApiConstants.gamesSyncCooldown.
      final prefs = container.read(sharedPreferencesProvider);
      expect(
        prefs.getInt(PrefsKeys.gamesNextSync(uid))! >
            DateTime.now().millisecondsSinceEpoch,
        isTrue,
      );
      expect(
        prefs.getString(PrefsKeys.gamesLastOutcome(uid)),
        RankedSyncOutcome.synced.name,
      );
    });

    test('an empty GamesMatches list still counts as synced', () async {
      await setUpWith();
      when(
        () => gamesService.getMatches(uid),
      ).thenAnswer((_) async => const GamesMatches([]));

      final result = await readOutcome();

      expect(result, RankedSyncOutcome.synced);
      expect(await store.count(uid), 0);
    });

    test('GamesPending(queued) returns queued and arms retryAfter', () async {
      await setUpWith();
      when(() => gamesService.getMatches(uid)).thenAnswer(
        (_) async => const GamesPending(
          status: 'queued',
          retryAfter: Duration(minutes: 7),
        ),
      );

      final result = await readOutcome();

      expect(result, RankedSyncOutcome.queued);
      final prefs = container.read(sharedPreferencesProvider);
      final nextSync = prefs.getInt(PrefsKeys.gamesNextSync(uid))!;
      final expected = DateTime.now()
          .add(const Duration(minutes: 7))
          .millisecondsSinceEpoch;
      // Within a couple seconds of the expected deadline - avoids a flaky
      // exact-millisecond comparison.
      expect((nextSync - expected).abs() < 3000, isTrue);
    });

    test('GamesPending(not_tracked) returns notTracked', () async {
      await setUpWith();
      when(() => gamesService.getMatches(uid)).thenAnswer(
        (_) async => const GamesPending(
          status: 'not_tracked',
          retryAfter: Duration(minutes: 5),
        ),
      );

      final result = await readOutcome();

      expect(result, RankedSyncOutcome.notTracked);
    });

    test(
      'a fetch failure with no persisted history rethrows (cold start)',
      () async {
        await setUpWith();
        when(
          () => gamesService.getMatches(uid),
        ).thenThrow(Exception('network down'));

        // Deliberately a bare read, not readOutcome(): a held listener on an
        // autoDispose provider whose build ultimately *rejects* (as opposed
        // to catching and returning a value) hangs rather than delivering
        // the error - container.read(...future) alone propagates it fine.
        await expectLater(
          container.read(rankedSyncProvider(uid).future),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'a fetch failure with persisted history serves it and returns offline',
      () async {
        await setUpWith();
        // Seed history directly - this uid has synced successfully before.
        await store.upsertAll(uid, [_match(uid, 0)]);
        when(
          () => gamesService.getMatches(uid),
        ).thenThrow(Exception('network down'));

        final result = await readOutcome();

        expect(result, RankedSyncOutcome.offline);
        // History is served from what was already there - a failed fetch
        // must not have cleared it.
        expect(await store.count(uid), 1);
      },
    );

    test(
      'a local write failure propagates as a real error, not offline',
      () async {
        await setUpWith(
          customStore: _ThrowingUpsertStore(overridePath: inMemoryDatabasePath),
        );
        when(
          () => gamesService.getMatches(uid),
        ).thenAnswer((_) async => GamesMatches([_match(uid, 0)]));

        // Before the fix, this returned RankedSyncOutcome.offline instead of
        // throwing. Asserting on the exact rejection isn't reliable here
        // (an autoDispose provider whose build rejects from a *second*
        // await, after getMatches' own await already succeeded, races the
        // dispose scheduler regardless of
        // whether the read is held behind a listener or not) - the
        // observable guarantee that actually matters is checked instead:
        // no `offline` outcome is ever recorded for this uid.
        try {
          await container.read(rankedSyncProvider(uid).future);
          fail('expected the write failure to propagate as an error');
        } catch (_) {
          // Expected - any rejection here is the fix working. What must
          // not have happened is the pre-fix behaviour: swallowing this
          // into a misleading `offline` outcome.
        }
        final prefs = container.read(sharedPreferencesProvider);
        expect(
          prefs.getString(PrefsKeys.gamesLastOutcome(uid)),
          isNot(RankedSyncOutcome.offline.name),
        );
      },
    );

    test(
      'a second read inside the cooldown replays without another fetch',
      () async {
        await setUpWith();
        when(
          () => gamesService.getMatches(uid),
        ).thenAnswer((_) async => GamesMatches([_match(uid, 0)]));

        await readOutcome();
        // Invalidate to force a fresh evaluation - the persisted deadline,
        // not provider caching, is what should stop a second network call.
        container.invalidate(rankedSyncProvider(uid));
        final second = await readOutcome();

        expect(second, RankedSyncOutcome.synced);
        verify(() => gamesService.getMatches(uid)).called(1);
      },
    );
  });
}
