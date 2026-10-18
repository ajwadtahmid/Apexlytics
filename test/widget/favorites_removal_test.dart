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

void main() {
  setUpAll(useFfiDatabase);

  var dbCounter = 0;

  // Three favorites, the last without a UID.
  const favorites =
      '[{"query":"Alpha","platform":"PC","uid":"1000000000001"},'
      '{"query":"Bravo","platform":"PC","uid":"1000000000002"},'
      '{"query":"Charlie","platform":"PS4"}]';

  Future<ProviderContainer> pumpPane(
    WidgetTester t, {
    String saved = favorites,
  }) async {
    SharedPreferences.setMockInitialValues({'search_favorites': saved});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        apiServiceProvider.overrideWithValue(
          ApiService(
            ApiCacheStore(
              overridePath:
                  'file:favorites_removal_${dbCounter++}?mode=memory&cache=shared',
            ),
            httpClientAdapter: FakeHttpAdapter(),
          ),
        ),
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
    await t.pump();
    return container;
  }

  List<String> names(ProviderContainer c) => [
    for (final f in c.read(searchStateProvider).favorites) f.query,
  ];

  Future<void> swipeAway(WidgetTester t, String name) async {
    await t.drag(find.text(name), const Offset(-600, 0));
    await t.pumpAndSettle();
  }

  group('swiping a favorite away', () {
    testWidgets('removes that one and says so', (t) async {
      final container = await pumpPane(t);

      await swipeAway(t, 'Bravo');

      expect(names(container), ['Alpha', 'Charlie']);
      expect(find.text('Bravo'), findsNothing);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Removed Bravo from favorites'), findsOneWidget);
    });

    testWidgets('Undo puts it back where it was', (t) async {
      final container = await pumpPane(t);
      await swipeAway(t, 'Bravo');

      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();

      expect(names(container), ['Alpha', 'Bravo', 'Charlie']);
      expect(find.text('Bravo'), findsOneWidget);
    });

    testWidgets('the removal is kept', (t) async {
      final container = await pumpPane(t);

      await swipeAway(t, 'Alpha');

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('search_favorites'), isNot(contains('Alpha')));
      expect(prefs.getString('search_favorites'), contains('Bravo'));
    });

    testWidgets('removes a favorite that has no UID as well', (t) async {
      final container = await pumpPane(t);

      await swipeAway(t, 'Charlie');

      expect(names(container), ['Alpha', 'Bravo']);
    });

    testWidgets('swiping the last one leaves the starting hint', (t) async {
      final container = await pumpPane(
        t,
        saved: '[{"query":"Alpha","platform":"PC","uid":"1000000000001"}]',
      );

      await swipeAway(t, 'Alpha');

      expect(names(container), isEmpty);
      expect(
        find.text('Search for a player above to get started'),
        findsOneWidget,
      );
    });

    testWidgets('a swipe the other way does nothing', (t) async {
      final container = await pumpPane(t);

      await t.drag(find.text('Bravo'), const Offset(600, 0));
      await t.pumpAndSettle();

      expect(names(container), ['Alpha', 'Bravo', 'Charlie']);
    });
  });

  group('pressing and holding a favorite', () {
    testWidgets('offers to remove it, which does', (t) async {
      final container = await pumpPane(t);

      await t.longPress(find.text('Alpha'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove from favorites'));
      await t.pumpAndSettle();

      expect(names(container), ['Bravo', 'Charlie']);
      expect(find.text('Removed Alpha from favorites'), findsOneWidget);
    });

    testWidgets('offers the website only for a player with a UID', (t) async {
      await pumpPane(t);

      await t.longPress(find.text('Alpha'));
      await t.pumpAndSettle();
      expect(find.text('Open on ALS'), findsOneWidget);

      await t.tapAt(const Offset(10, 10)); // dismiss the sheet
      await t.pumpAndSettle();
      await t.longPress(find.text('Charlie'));
      await t.pumpAndSettle();

      expect(find.text('Remove from favorites'), findsOneWidget);
      expect(find.text('Open on ALS'), findsNothing);
    });
  });
}
