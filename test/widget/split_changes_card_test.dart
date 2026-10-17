import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/screens/ranked/widgets/split_changes_card.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

List<RankedMatch> _games(String legend, String map, int n, int rp) => [
  for (var i = 0; i < n; i++)
    buildMatch(
      legend: legend,
      map: map,
      rp: rp,
      start: 1782090000 + legend.hashCode % 1000 + i * 5000,
    ),
];

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<RankedMatch> a,
    List<RankedMatch> b,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SplitChangesCard(
              legendsA: legendBreakdowns(a),
              legendsB: legendBreakdowns(b),
              mapsA: mapBreakdowns(a),
              mapsB: mapBreakdowns(b),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the legends and maps that moved most', (tester) async {
    await pump(
      tester,
      [
        ..._games('Axle', 'olympus_rotation', 6, 10),
        ..._games('Bangalore', 'olympus_rotation', 4, 10),
      ],
      [
        ..._games('Axle', 'olympus_rotation', 2, -5),
        ..._games('Wraith', 'olympus_rotation', 8, -5),
      ],
    );

    expect(find.text('What changed'), findsOneWidget);
    expect(find.text('Wraith'), findsOneWidget);
    expect(find.text('+80 pts'), findsOneWidget);
    expect(find.text('0% → 80%'), findsOneWidget);
    expect(find.text('-40 pts'), findsNWidgets(2));
    // Olympus went from +10 a game to -5.
    expect(find.text('Olympus'), findsOneWidget);
    expect(find.text('-15.0'), findsOneWidget);
    expect(find.text('+10.0 → -5.0'), findsOneWidget);
  });

  testWidgets('leaves out the map block when no map has enough games', (
    tester,
  ) async {
    await pump(
      tester,
      [..._games('Axle', 'olympus_rotation', 2, 10)],
      [..._games('Wraith', 'storm_point_rotation', 2, 10)],
    );

    expect(find.text('Legends picked differently'), findsOneWidget);
    expect(find.text('RP per game by map'), findsNothing);
  });

  testWidgets('is not there at all when nothing moved', (tester) async {
    final same = [..._games('Axle', 'olympus_rotation', 4, 10)];
    await pump(tester, same, same);

    expect(find.text('What changed'), findsNothing);
  });
}
