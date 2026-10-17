import 'package:apexlytics/screens/ranked/ranked_personal_records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  // Three wins in a row, ending the scope.
  final matches = [
    buildMatch(start: 1782090000 + 3 * 1000, rp: 10),
    buildMatch(start: 1782090000 + 2 * 1000, rp: 10),
    buildMatch(start: 1782090000 + 1 * 1000, rp: 10),
  ];

  Future<void> pump(WidgetTester tester, {required bool live}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RankedPersonalRecordsScreen(
            uid: '1',
            matches: matches,
            splits: const [],
            live: live,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the screen is called Records & Compare', (tester) async {
    await pump(tester, live: true);

    expect(find.text('Records & Compare'), findsOneWidget);
    expect(find.text('Comparison'), findsOneWidget);
  });

  testWidgets('a live scope tells the player they are on the streak now', (
    tester,
  ) async {
    await pump(tester, live: true);

    expect(find.text('3 games'), findsOneWidget);
    expect(find.text('You\'re on it now!'), findsOneWidget);
    expect(find.textContaining('since '), findsOneWidget);
  });

  testWidgets('a past week or split never says the player is on it now', (
    tester,
  ) async {
    // An old scope's trailing run isn't the player's streak today.
    await pump(tester, live: false);

    expect(find.text('3 games'), findsOneWidget);
    expect(find.text('You\'re on it now!'), findsNothing);
    expect(find.text('Ended on its best streak'), findsOneWidget);
    expect(find.textContaining('Currently'), findsNothing);
    expect(find.textContaining('since '), findsNothing);
    expect(find.textContaining('from '), findsOneWidget);
  });
}
