import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:apexlytics/app.dart';
import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/search/search_screen.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:apexlytics/widgets/player_lookup_form.dart';

import 'helpers.dart';

/// Prefs with the one-time UID-search warning dialog already dismissed, so
/// tapping the toggle in a test doesn't need to also handle that dialog.
Future<SharedPreferences> _prefsUidWarningSeen() async {
  SharedPreferences.setMockInitialValues({
    PrefsKeys.uidSearchWarningShown: true,
  });
  return SharedPreferences.getInstance();
}

// Bare `inMemoryDatabasePath` (':memory:') opens in shared-cache mode under
// sqflite_common_ffi, so every store using that literal path in this process
// would alias to the *same* database — a uniquely-named in-memory URI per
// call keeps each test's ApiService genuinely isolated (see api_cache_test.dart).
var _apiCacheDbCounter = 0;

/// A fresh, isolated ApiService for one test — its cache store is an
/// in-memory sqlite db (see setUpAll), not the real api_cache.db, and its transport is [adapter].
ApiService _buildApiService([FakeHttpAdapter? adapter]) => ApiService(
  ApiCacheStore(
    overridePath: 'file:widget_test_api_cache_${_apiCacheDbCounter++}?mode=memory&cache=shared',
  ),
  httpClientAdapter: adapter ?? FakeHttpAdapter(),
);

/// Wraps [widget] in the minimal scaffolding needed for Riverpod + Material.
Widget _wrap(Widget widget, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: widget),
    ),
  );
}

void main() {
  late SharedPreferences prefs;

  // sqflite has no native binding under `flutter test` (host VM) — use FFI.
  // ApiService now opens an ApiCacheStore (sqlite) on construction, which
  // needs this even though these tests never inspect its contents.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('App smoke test', () {
    testWidgets('renders MaterialApp without exception', (tester) async {
      final adapter = FakeHttpAdapter();
      final apiService = _buildApiService(adapter);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiServiceProvider.overrideWithValue(apiService),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1080, 1920);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ApexLegendsApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));

      expect(find.byType(MaterialApp), findsOneWidget);
      // The startup prefetch went to the fake transport, and only there.
      expect(
        adapter.paths,
        containsAll(['/maprotation', '/predator', '/servers']),
      );
    });
  });

  group('PlayerLookupForm', () {
    testWidgets('renders text field and submit button', (tester) async {
      await tester.pumpWidget(
        _wrap(const PlayerLookupForm(submitLabel: 'Find Player'), prefs),
      );
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Find Player'), findsOneWidget);
    });

    testWidgets('shows error on empty name submit', (tester) async {
      await tester.pumpWidget(
        _wrap(const PlayerLookupForm(submitLabel: 'Find Player'), prefs),
      );
      await tester.pump();

      await tester.tap(find.text('Find Player'));
      await tester.pump();

      expect(find.text('Enter a player name.'), findsOneWidget);
    });

    testWidgets('pre-fills initialName when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PlayerLookupForm(
            submitLabel: 'Update',
            initialName: 'Aceu',
            initialPlatform: 'PC',
          ),
          prefs,
        ),
      );
      await tester.pump();
      expect(find.text('Aceu'), findsOneWidget);
    });

    testWidgets('platform picker shows PC option', (tester) async {
      await tester.pumpWidget(
        _wrap(const PlayerLookupForm(submitLabel: 'Search'), prefs),
      );
      await tester.pump();
      expect(find.text('PC'), findsWidgets);
    });

    testWidgets('UID mode strips non-digit characters as they are typed', (
      tester,
    ) async {
      final uidPrefs = await _prefsUidWarningSeen();
      await tester.pumpWidget(
        _wrap(const PlayerLookupForm(submitLabel: 'Find Player'), uidPrefs),
      );
      await tester.pump();

      await tester.tap(find.byType(Switch));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'abc123');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '123');
    });

    testWidgets(
      'switching to UID mode clears the field, and switching back restores '
      'the name',
      (tester) async {
        final uidPrefs = await _prefsUidWarningSeen();
        await tester.pumpWidget(
          _wrap(
            const PlayerLookupForm(
              submitLabel: 'Update',
              initialName: 'Aceu',
              initialPlatform: 'PC',
            ),
            uidPrefs,
          ),
        );
        await tester.pump();
        expect(find.text('Aceu'), findsOneWidget);

        await tester.tap(find.byType(Switch));
        await tester.pump();

        var field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, isEmpty);
        expect(find.text('UID must contain digits only.'), findsNothing);

        await tester.tap(find.byType(Switch));
        await tester.pump();

        field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, 'Aceu');
      },
    );
  });

  group('SearchScreen', () {
    testWidgets('renders search form on load', (tester) async {
      final apiService = _buildApiService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiServiceProvider.overrideWithValue(apiService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TextField), findsWidgets);
      expect(find.text('PC'), findsWidgets);
    });

    testWidgets('ignores empty search submission', (tester) async {
      final apiService = _buildApiService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiServiceProvider.overrideWithValue(apiService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // SearchScreen silently ignores empty search submissions
      final submitButton = find.byIcon(Icons.arrow_forward);
      expect(submitButton, findsOneWidget);

      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Verify we're still on SearchScreen (no navigation happened)
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('UID mode strips non-digit characters as they are typed', (
      tester,
    ) async {
      final uidPrefs = await _prefsUidWarningSeen();
      final apiService = _buildApiService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(uidPrefs),
          apiServiceProvider.overrideWithValue(apiService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(Switch));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'abc123');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '123');
    });

    testWidgets('switching to UID mode clears the bar, and switching back '
        'restores the typed name', (tester) async {
      final uidPrefs = await _prefsUidWarningSeen();
      final apiService = _buildApiService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(uidPrefs),
          apiServiceProvider.overrideWithValue(apiService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Aceu');
      await tester.pump();

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      var field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      expect(find.text('UID must contain digits only.'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Aceu');
    });
  });
}
