import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/search/player_result_page.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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

  testWidgets('Back on the error screen leaves the page', (t) async {
    await open(t, byUid: false);

    await t.tap(find.text('Back'));
    await t.pumpAndSettle();

    // It was the only route, so popping it leaves nothing to show.
    expect(find.byType(PlayerResultPage), findsNothing);
  });
}
