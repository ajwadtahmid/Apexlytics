import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/search/player_result_page.dart';
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

  Future<FakeHttpAdapter> open(
    WidgetTester t, {
    required bool byUid,
    String query = 'Nobody',
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = FakeHttpAdapter(); // every route answers 404
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiServiceProvider.overrideWithValue(
          ApiService(
            ApiCacheStore(
              overridePath:
                  'file:not_found_${dbCounter++}?mode=memory&cache=shared',
            ),
            httpClientAdapter: adapter,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PlayerResultPage(
            query: query,
            platform: 'PC',
            searchByUid: byUid,
          ),
        ),
      ),
    );
    // Give the request a few real async turns, stopping once the spinner is gone.
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    return adapter;
  }

  // Riverpod's default retries kept this page spinning ~30 s over eleven requests; waiting out
  // the longest backoff proves none are sent.
  Future<void> waitOutRetries(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(seconds: 10));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
  }

  testWidgets('a player who does not exist shows the error straight away, '
      'after one request', (t) async {
    final adapter = await open(t, byUid: false);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.search_off), findsOneWidget);
    expect(
      find.text('Player not found. Check the name and platform.'),
      findsOneWidget,
    );
    await waitOutRetries(t);
    expect(adapter.paths, ['/player']);
    expect(find.byIcon(Icons.search_off), findsOneWidget);
  });

  testWidgets('the same for a UID search', (t) async {
    final adapter = await open(t, byUid: true, query: '1234567890');

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.search_off), findsOneWidget);
    await waitOutRetries(t);
    expect(adapter.paths, ['/player/uid']);
  });

  group('trying another platform', () {
    testWidgets('a name search offers the other platforms that take names', (
      t,
    ) async {
      await open(t, byUid: false);

      expect(find.text('Try another platform'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'PlayStation'), findsOne);
      expect(find.widgetWithText(OutlinedButton, 'Xbox'), findsOneWidget);
      // Not the platform just tried, and not one that has no name lookup.
      expect(find.widgetWithText(OutlinedButton, 'PC'), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'Nintendo Switch'),
        findsNothing,
      );
    });

    testWidgets('a UID search offers every other platform, Switch included', (
      t,
    ) async {
      await open(t, byUid: true, query: '1234567890');

      for (final label in ['PlayStation', 'Xbox', 'Nintendo Switch']) {
        expect(find.widgetWithText(OutlinedButton, label), findsOneWidget);
      }
      expect(find.widgetWithText(OutlinedButton, 'PC'), findsNothing);
    });

    testWidgets('a button runs the same lookup on that platform', (t) async {
      final adapter = await open(t, byUid: false);
      expect(adapter.requests.single.queryParameters['platform'], 'PC');

      await t.tap(find.widgetWithText(OutlinedButton, 'Xbox'));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(milliseconds: 100));
        if (adapter.requests.length > 1) break;
      }

      final retry = adapter.requests.last;
      expect(retry.queryParameters['platform'], 'X1');
      expect(retry.queryParameters['player'], 'nobody');
    });

    testWidgets('it replaces the page, so Back returns to Search', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiServiceProvider.overrideWithValue(
            ApiService(
              ApiCacheStore(
                overridePath:
                    'file:not_found_${dbCounter++}?mode=memory&cache=shared',
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
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PlayerResultPage(
                        query: 'Nobody',
                        platform: 'PC',
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(milliseconds: 100));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }

      await t.tap(find.widgetWithText(OutlinedButton, 'Xbox'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.byType(BackButton));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      // One Back from the retried lookup, not two.
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('a failure that is not "not found" offers none', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiServiceProvider.overrideWithValue(
            ApiService(
              ApiCacheStore(
                overridePath:
                    'file:not_found_${dbCounter++}?mode=memory&cache=shared',
              ),
              httpClientAdapter: FakeHttpAdapter({
                '/player': const FakeReply(500, {'error': 'boom'}),
              }),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: PlayerResultPage(query: 'Someone', platform: 'PC'),
          ),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(seconds: 2));
        if (find.byIcon(Icons.search_off).evaluate().isNotEmpty) break;
      }

      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expect(find.text('Try another platform'), findsNothing);
    });
  });

  testWidgets('Back on the error screen leaves the page', (t) async {
    await open(t, byUid: false);

    await t.tap(find.text('Back'));
    await t.pumpAndSettle();

    // It was the only route, so popping it leaves nothing to show.
    expect(find.byType(PlayerResultPage), findsNothing);
  });
}
