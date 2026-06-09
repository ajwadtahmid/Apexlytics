import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/app.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/search/search_screen.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/widgets/player_lookup_form.dart';

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('App smoke test', () {
    testWidgets('renders MaterialApp without exception', (tester) async {
      final apiService = ApiService(prefs);
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
  });

  group('SearchScreen', () {
    testWidgets('renders search form on load', (tester) async {
      final apiService = ApiService(prefs);
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
      final apiService = ApiService(prefs);
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
  });
}
