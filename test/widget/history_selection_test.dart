import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/widgets/match_history_list.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

void main() {
  setUpAll(useFfiDatabase);

  late RankedHistoryStore store;
  late List<RankedMatch> games;

  Future<void> pump(WidgetTester tester, {bool selectable = true}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.runAsync(() async {
      store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
      games = [
        for (var i = 0; i < 3; i++)
          buildMatch(start: 1782090000 + (2 - i) * 1000, rp: 10 + i),
      ];
      await store.upsertAll('1', games);
    });
    addTearDown(store.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          rankedHistoryStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MatchHistoryList(
              matches: games,
              onRefresh: () async {},
              header: const Text('HEADER'),
              selectable: selectable,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'a long press starts a selection and swaps the header for a bar',
    (tester) async {
      await pump(tester);
      expect(find.text('HEADER'), findsOneWidget);

      await tester.longPress(find.text('Axle').first);
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('HEADER'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    },
  );

  testWidgets('taps add to the selection, and closing it ends it', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(find.text('Axle').first);
    await tester.pump();
    await tester.tap(find.text('Axle').at(1));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('3 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pump();
    expect(find.text('HEADER'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('Exclude marks the picked games excluded and clears the bar', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(find.text('Axle').first);
    await tester.pump();
    await tester.tap(find.text('Axle').at(1));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Exclude'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    final stored = await tester.runAsync(() => store.getAll('1'));
    expect(stored!.where((m) => m.excluded), hasLength(2));
    expect(find.text('Excluded 2 games'), findsOneWidget);
    expect(find.text('HEADER'), findsOneWidget);
  });

  testWidgets('a list that is not selectable ignores a long press', (
    tester,
  ) async {
    await pump(tester, selectable: false);

    await tester.longPress(find.text('Axle').first);
    await tester.pump();

    expect(find.textContaining('selected'), findsNothing);
    expect(find.text('HEADER'), findsOneWidget);
  });
}
