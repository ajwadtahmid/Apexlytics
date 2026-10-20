import 'dart:convert';

import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/search_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/search/favorites_pane.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// A favorite's card once the live lookup is gone: it shows what was last seen
/// of the player, with its age, instead of going blank.
void main() {
  setUpAll(useFfiDatabase);

  var dbCounter = 0;

  Map<String, Object?> snapshot({
    required String name,
    required String rank,
    required int rp,
    required Duration age,
  }) => {
    'name': name,
    'rank': rank,
    'rp': rp,
    'at': DateTime.now().subtract(age).millisecondsSinceEpoch,
  };

  String favorites(List<Map<String, Object?>> list) => jsonEncode(list);

  /// A cached /player/uid response for [uid], saved [age] ago.
  Future<void> seedCache(
    ApiCacheStore store, {
    required String uid,
    required String name,
    required String rank,
    required int rp,
    required Duration age,
  }) => store.upsert(
    Uri(
      path: '/player/uid',
      queryParameters: {'platform': 'PC', 'uid': uid}, // keys are sorted
    ).toString(),
    jsonEncode({
      'global': {
        'name': name,
        'uid': uid,
        'platform': 'PC',
        'level': 10,
        'rank': {'rankName': rank, 'rankScore': rp, 'rankDiv': 2},
      },
      'realtime': {'isOnline': 0, 'isInGame': 0},
    }),
    DateTime.now().subtract(age).millisecondsSinceEpoch,
  );

  Future<ProviderContainer> pumpPane(
    WidgetTester t, {
    required String saved,
    String recents = '[]',
    Future<void> Function(ApiCacheStore store)? seed,
  }) async {
    SharedPreferences.setMockInitialValues({
      'search_favorites': saved,
      'recent_searches': recents,
    });
    final store = ApiCacheStore(
      overridePath:
          'file:favorites_snapshot_${dbCounter++}?mode=memory&cache=shared',
    );
    if (seed != null) await t.runAsync(() => seed(store));
    final api = ApiService(store, httpClientAdapter: FakeHttpAdapter({}));
    // The cache fills from disk in the background, long before a card shows in
    // the app; a card reads it once, as it builds.
    if (seed != null) {
      await t.runAsync(() async {
        for (var i = 0; i < 100 && api.cacheUsage.entries == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
    }
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        apiServiceProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: FavoritesPane(onPick: (_) {})),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    return container;
  }

  testWidgets('with nothing cached, the saved figures and their age show', (
    t,
  ) async {
    await pumpPane(
      t,
      saved: favorites([
        {
          'query': 'Alpha',
          'platform': 'PC',
          'uid': '1',
          'snapshot': snapshot(
            name: 'AlphaNow',
            rank: 'Master',
            rp: 52671,
            age: const Duration(days: 3, hours: 2),
          ),
        },
      ]),
    );

    expect(find.text('AlphaNow'), findsOneWidget);
    expect(find.text('PC · Master · 3d ago'), findsOneWidget);
    expect(find.text('52,671'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNothing);
  });

  testWidgets('figures under a day old are not labelled with an age', (
    t,
  ) async {
    await pumpPane(
      t,
      saved: favorites([
        {
          'query': 'Alpha',
          'platform': 'PC',
          'uid': '1',
          'snapshot': snapshot(
            name: 'Alpha',
            rank: 'Master',
            rp: 52671,
            age: const Duration(hours: 5),
          ),
        },
      ]),
    );

    expect(find.text('PC · Master'), findsOneWidget);
  });

  testWidgets('a favorite saved before snapshots existed still has the '
      'placeholder, not an error', (t) async {
    await pumpPane(t, saved: '[{"query":"Alpha","platform":"PC","uid":"1"}]');

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('PC'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('an expired cached response fills the card for a favorite '
      'that has no snapshot yet', (t) async {
    await pumpPane(
      t,
      saved: '[{"query":"Alpha","platform":"PC","uid":"1"}]',
      seed: (store) => seedCache(
        store,
        uid: '1',
        name: 'Alpha',
        rank: 'Platinum',
        rp: 10330,
        age: const Duration(days: 2),
      ),
    );

    expect(find.text('PC · Platinum II · 2d ago'), findsOneWidget);
    expect(find.text('10,330'), findsOneWidget);
  });

  testWidgets('the newer of the cached response and the snapshot wins', (
    t,
  ) async {
    await pumpPane(
      t,
      saved: favorites([
        {
          'query': 'Alpha',
          'platform': 'PC',
          'uid': '1',
          'snapshot': snapshot(
            name: 'Alpha',
            rank: 'Gold',
            rp: 5000,
            age: const Duration(days: 5),
          ),
        },
        {
          'query': 'Bravo',
          'platform': 'PC',
          'uid': '2',
          'snapshot': snapshot(
            name: 'Bravo',
            rank: 'Gold',
            rp: 5000,
            age: const Duration(days: 1, hours: 1),
          ),
        },
      ]),
      seed: (store) async {
        // Newer than Alpha's snapshot, older than Bravo's.
        for (final (uid, name) in [('1', 'Alpha'), ('2', 'Bravo')]) {
          await seedCache(
            store,
            uid: uid,
            name: name,
            rank: 'Platinum',
            rp: 10330,
            age: const Duration(days: 2),
          );
        }
      },
    );

    expect(find.text('10,330'), findsOneWidget, reason: 'Alpha: the cache');
    expect(find.text('5,000'), findsOneWidget, reason: 'Bravo: the snapshot');
  });

  testWidgets('saving a recent lookup keeps what its card was showing', (
    t,
  ) async {
    final container = await pumpPane(
      t,
      saved: '[]',
      recents: '[{"query":"Echo","platform":"PC","uid":"7"}]',
      seed: (store) => seedCache(
        store,
        uid: '7',
        name: 'Echo',
        rank: 'Diamond',
        rp: 11000,
        age: const Duration(days: 2),
      ),
    );

    await t.tap(find.byTooltip('Add to favorites'));
    await t.pump();

    final snap = container.read(searchStateProvider).favorites.single.snapshot;
    expect(snap?.rankScore, 11000);
    expect(snap?.rank, 'Diamond');
  });
}
