import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/screens/ranked/ranked_compare_tab.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_entity_compare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

List<RankedMatch> _games(
  String legend,
  String map,
  int n,
  int rp,
  int seed, {
  int? kills,
  int? damage,
}) => [
  for (var i = 0; i < n; i++)
    buildMatch(
      legend: legend,
      map: map,
      rp: rp,
      kills: kills,
      damage: damage,
      start: 1782090000 + (seed + i) * 5000,
    ),
];

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  final matches = [
    ..._games('Axle', 'olympus_rotation', 6, 20, 0, kills: 3, damage: 800),
    ..._games(
      'Bangalore',
      'storm_point_rotation',
      4,
      -10,
      10,
      kills: 1,
      damage: 400,
    ),
    ..._games('Wraith', 'olympus_rotation', 2, 30, 20),
  ];

  group('comparing legends', () {
    testWidgets('defaults to the two most played and lines up their figures', (
      tester,
    ) async {
      await pump(
        tester,
        RankedEntityCompare(kind: CompareKind.legends, matches: matches),
      );

      expect(find.text('Axle · 6 games'), findsOneWidget);
      expect(find.text('Bangalore · 4 games'), findsOneWidget);
      // Games: 6 vs 4. Net RP: +120 vs -40. RP/game: +20.0 vs -10.0.
      expect(find.text('+120'), findsOneWidget);
      expect(find.text('-40'), findsOneWidget);
      expect(find.text('+20.0'), findsOneWidget);
      expect(find.text('-10.0'), findsOneWidget);
      // Avg kills 3.0 vs 1.0, and the change from first to second.
      expect(find.text('3.0'), findsOneWidget);
      expect(find.text('-2.0'), findsOneWidget);
    });

    testWidgets('choosing another legend updates the table', (tester) async {
      await pump(
        tester,
        RankedEntityCompare(kind: CompareKind.legends, matches: matches),
      );

      await tester.tap(find.text('Bangalore · 4 games'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wraith · 2 games').last);
      await tester.pumpAndSettle();

      // Wraith's two games netted +60, and she has no kills or damage readings.
      expect(find.text('+60'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('warns when a side has too few games to mean much', (
      tester,
    ) async {
      await pump(
        tester,
        RankedEntityCompare(kind: CompareKind.legends, matches: matches),
      );
      expect(find.textContaining('too few'), findsNothing);

      await tester.tap(find.text('Bangalore · 4 games'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wraith · 2 games').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('too few'), findsOneWidget);
    });

    testWidgets('asks for more play when there is only one legend', (
      tester,
    ) async {
      await pump(
        tester,
        RankedEntityCompare(
          kind: CompareKind.legends,
          matches: _games('Axle', 'olympus_rotation', 5, 10, 0),
        ),
      );

      expect(find.textContaining('at least two legends'), findsOneWidget);
    });
  });

  testWidgets('comparing maps works the same way', (tester) async {
    await pump(
      tester,
      RankedEntityCompare(kind: CompareKind.maps, matches: matches),
    );

    // Olympus has 8 games (Axle's 6 and Wraith's 2), Storm Point 4.
    expect(find.text('Olympus · 8 games'), findsOneWidget);
    expect(find.text('Storm Point · 4 games'), findsOneWidget);
    expect(find.text('+180'), findsOneWidget); // 6 x 20 + 2 x 30
  });

  group('the Comparison selector', () {
    testWidgets('starts on splits and switches to legends and maps', (
      tester,
    ) async {
      await pump(
        tester,
        RankedCompareTab(uid: '1', splits: const [], matches: matches),
      );

      expect(find.text('Splits'), findsOneWidget);
      expect(find.textContaining('at least two splits'), findsOneWidget);

      await tester.tap(find.text('Legends'));
      await tester.pumpAndSettle();
      expect(find.text('Axle · 6 games'), findsOneWidget);
      expect(find.textContaining('at least two splits'), findsNothing);

      await tester.tap(find.text('Maps'));
      await tester.pumpAndSettle();
      expect(find.text('Olympus · 8 games'), findsOneWidget);
    });
  });

  testWidgets('the Compare entry opens the comparison page', (tester) async {
    await pump(
      tester,
      RankedCompareEntry(uid: '1', splits: const [], matches: matches),
    );

    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    expect(find.text('Compare'), findsOneWidget); // the page title
    expect(find.text('Splits'), findsOneWidget);
    await tester.tap(find.text('Legends'));
    await tester.pumpAndSettle();
    expect(find.text('Axle · 6 games'), findsOneWidget);
  });
}
