import 'dart:async';
import 'dart:typed_data';

import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/stats/stats_screen.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

Map<String, Object?> playerJson(String name, String uid) => {
  'global': {
    'name': name,
    'uid': uid,
    'platform': 'PC',
    'level': 10,
    'rank': {'rankName': 'Gold', 'rankScore': 5000},
  },
};

FakeHttpAdapter _adapter({Object? games = const <Object?>[]}) =>
    FakeHttpAdapter({
      '/player/uid': (RequestOptions o) => playerJson(
        'P${o.queryParameters['uid']}',
        '${o.queryParameters['uid']}',
      ),
      '/games': games,
    });

const _twoProfiles =
    '[{"name":"Alpha","uid":"1000000001","platform":"PC"},'
    '{"name":"Bravo","uid":"1000000002","platform":"PC"}]';
const _oneProfile = '[{"name":"Alpha","uid":"1000000001","platform":"PC"}]';

/// Holds back the second profile's stats until [gate] completes, so a test can
/// look at the screen part-way through a run.
class _HoldsSecondProfile extends FakeHttpAdapter {
  final Future<void> gate;
  _HoldsSecondProfile(super.routes, this.gate);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.queryParameters['uid'] == '1000000002') await gate;
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  setUpAll(useFfiDatabase);

  var dbCounter = 0;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// Polls in real time until [done]; a run has several async steps per profile.
  Future<void> pumpUntil(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> boot(
    WidgetTester t, {
    required bool owner,
    required String profiles,
    FakeHttpAdapter? adapter,
  }) async {
    final later = DateTime.now()
        .add(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      if (owner) 'owner_unlocked': true,
      'player_profiles': profiles,
      'active_profile_index': 0,
      // Inside the backoff window, so the screen replays a stored outcome (a failing /games would
      // be retried by Riverpod and keep the app bar on its spinner).
      for (final uid in ['1000000001', '1000000002']) ...{
        'games_next_sync_$uid': later,
        'games_last_outcome_$uid': 'synced',
      },
    });
    final prefs = await SharedPreferences.getInstance();
    final store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    addTearDown(store.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rankedHistoryStoreProvider.overrideWithValue(store),
        apiServiceProvider.overrideWithValue(
          ApiService(
            ApiCacheStore(
              overridePath:
                  'file:refresh_btn_${dbCounter++}?mode=memory&cache=shared',
            ),
            httpClientAdapter: adapter ?? _adapter(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: StatsScreen()),
      ),
    );
    await t.pump();
    await settle(t);
  }

  // The stats view runs its own requests and a refresh timer.
  Future<void> teardown(WidgetTester t) async {
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  }

  group('the app bar button', () {
    testWidgets('an owner with several profiles gets "Refresh all"', (t) async {
      await boot(t, owner: true, profiles: _twoProfiles);

      expect(find.byTooltip('Refresh all profiles'), findsOneWidget);
      expect(find.byTooltip('Sync'), findsNothing);
      await teardown(t);
    });

    testWidgets('anyone else keeps the plain sync button', (t) async {
      await boot(t, owner: false, profiles: _twoProfiles);

      expect(find.byTooltip('Sync'), findsOneWidget);
      expect(find.byTooltip('Refresh all profiles'), findsNothing);
      await teardown(t);
    });

    testWidgets('an owner with a single profile keeps the plain sync button', (
      t,
    ) async {
      await boot(t, owner: true, profiles: _oneProfile);

      expect(find.byTooltip('Sync'), findsOneWidget);
      expect(find.byTooltip('Refresh all profiles'), findsNothing);
      await teardown(t);
    });
  });

  group('running it', () {
    testWidgets('the app bar says which profile it is on', (t) async {
      final release = Completer<void>();
      final adapter = _HoldsSecondProfile({
        '/player/uid': (RequestOptions o) => playerJson(
          'P${o.queryParameters['uid']}',
          '${o.queryParameters['uid']}',
        ),
        '/games': const <Object?>[],
      }, release.future);
      await boot(t, owner: true, profiles: _twoProfiles, adapter: adapter);
      expect(find.textContaining('Refreshing'), findsNothing);

      await t.tap(find.byTooltip('Refresh all profiles'));
      await t.pump();
      // The first profile finishes; the second is held.
      await pumpUntil(
        t,
        () => find.text('Refreshing 2/2').evaluate().isNotEmpty,
      );
      expect(find.text('Refreshing 2/2'), findsOneWidget);

      release.complete();
      await pumpUntil(
        t,
        () => find.text('Refreshed 2 profiles').evaluate().isNotEmpty,
      );
      expect(find.textContaining('Refreshing'), findsNothing);
      await teardown(t);
    });

    testWidgets('a clean run says so in a snackbar', (t) async {
      final adapter = _adapter();
      await boot(t, owner: true, profiles: _twoProfiles, adapter: adapter);

      await t.tap(find.byTooltip('Refresh all profiles'));
      await t.pump();
      await pumpUntil(
        t,
        () => find.text('Refreshed 2 profiles').evaluate().isNotEmpty,
      );

      expect(find.text('Refreshed 2 profiles'), findsOneWidget);
      expect(find.text('Refresh all'), findsNothing);
      // Both profiles were fetched, not just the one on screen.
      final games = adapter.requests
          .where((r) => r.path == '/games')
          .map((r) => r.queryParameters['uid']);
      expect(games, containsAll(['1000000001', '1000000002']));
      await teardown(t);
    });

    testWidgets('a run with problems opens the results, profile by profile', (
      t,
    ) async {
      // Stats come back fine; the history server refuses both profiles.
      await boot(
        t,
        owner: true,
        profiles: _twoProfiles,
        adapter: _adapter(games: const FakeReply(404, {'error': 'nope'})),
      );

      await t.tap(find.byTooltip('Refresh all profiles'));
      await t.pump();
      await pumpUntil(t, () => find.text('Refresh all').evaluate().isNotEmpty);
      await t.pumpAndSettle();

      expect(find.text('Refresh all'), findsOneWidget); // the sheet's title
      expect(find.textContaining('Alpha'), findsWidgets);
      expect(find.textContaining('Bravo'), findsWidgets);
      expect(find.text("Couldn't fetch history"), findsNWidgets(2));
      expect(find.text('Stats updated'), findsNWidgets(2));
      await teardown(t);
    });
  });
}
