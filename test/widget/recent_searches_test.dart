import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/search_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/search/favorites_pane.dart';
import 'package:apexlytics/screens/search/player_result_page.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import 'refresh_all_button_test.dart' show playerJson;

void main() {
  setUpAll(useFfiDatabase);

  var dbCounter = 0;

  Future<ProviderContainer> containerWith(
    FakeHttpAdapter adapter, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        apiServiceProvider.overrideWithValue(
          ApiService(
            ApiCacheStore(
              overridePath:
                  'file:recent_${dbCounter++}?mode=memory&cache=shared',
            ),
            httpClientAdapter: adapter,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  group('the Recent list on the Search screen', () {
    Future<ProviderContainer> pumpPane(
      WidgetTester t, {
      String favorites = '[]',
    }) async {
      final container = await containerWith(
        FakeHttpAdapter(),
        prefs: {
          'search_favorites': favorites,
          'recent_searches':
              '[{"query":"Alpha","platform":"PC","uid":"1000000000001"},'
              '{"query":"Bravo","platform":"PS4","uid":"1000000000002"}]',
        },
      );
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: FavoritesPane(onPick: (_) {})),
          ),
        ),
      );
      await t.pump();
      return container;
    }

    testWidgets('shows recent lookups, newest first', (t) async {
      await pumpPane(t);

      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Alpha')).dy,
        lessThan(t.getTopLeft(find.text('Bravo')).dy),
      );
      expect(
        find.text('Search for a player above to get started'),
        findsNothing,
      );
    });

    testWidgets('the star adds that player to favourites', (t) async {
      final container = await pumpPane(t);

      await t.tap(find.byTooltip('Add to favorites').first);
      await t.pump();

      expect(
        container.read(searchStateProvider).favorites.single.uid,
        '1000000000001',
      );
      // Now a favourite, so it isn't also listed under Recent.
      expect(find.byTooltip('Add to favorites'), findsOneWidget);
    });

    testWidgets('Clear empties the list', (t) async {
      final container = await pumpPane(t);

      await t.tap(find.text('Clear'));
      await t.pump();

      expect(container.read(searchStateProvider).recents, isEmpty);
      expect(find.text('Recent'), findsNothing);
    });

    testWidgets('with nothing recent or saved it keeps the starting hint', (
      t,
    ) async {
      final container = await containerWith(FakeHttpAdapter());
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: FavoritesPane(onPick: (_) {})),
          ),
        ),
      );
      await t.pump();

      expect(
        find.text('Search for a player above to get started'),
        findsOneWidget,
      );
    });
  });

  group('recording a lookup', () {
    Future<ProviderContainer> open(
      WidgetTester t,
      FakeHttpAdapter adapter,
    ) async {
      final container = await containerWith(adapter);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: PlayerResultPage(query: 'Found', platform: 'PC'),
          ),
        ),
      );
      await settle(t);
      // Unmounted, so the page's refresh timer doesn't outlive the test.
      await t.pumpWidget(const SizedBox.shrink());
      return container;
    }

    testWidgets('a player who was found is remembered by their real name', (
      t,
    ) async {
      final container = await open(
        t,
        FakeHttpAdapter({
          '/player': playerJson('FoundRealName', '1000000000007'),
          '/games': const <Object?>[],
        }),
      );

      final recents = container.read(searchStateProvider).recents;
      expect(recents, hasLength(1));
      expect(recents.single.query, 'FoundRealName');
      expect(recents.single.uid, '1000000000007');
      container.dispose(); // its providers' timers must not outlive the test
    });

    testWidgets('a lookup that found nobody leaves no trace', (t) async {
      final container = await open(
        t,
        FakeHttpAdapter(),
      ); // every route is a 404

      expect(container.read(searchStateProvider).recents, isEmpty);
    });
  });
}
