import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/widgets/player_stats_tabs.dart';

import '../helpers.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<LegendStat> legends) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlayerStatsTabs(legendStats: legends),
            ),
          ),
        ),
      );

  LegendStat wraith(int kills) => buildLegend(
    name: 'Wraith',
    trackers: [buildTracker(key: 'kills', value: kills)],
  );

  testWidgets('a refresh with the same legends shows the new tracker values', (
    tester,
  ) async {
    await pump(tester, [wraith(111)]);
    expect(find.text('111'), findsWidgets);

    // Pull-to-refresh rebuilds the same widget with fresh stats: same legend
    // name and order, new numbers.
    await pump(tester, [wraith(222)]);

    expect(find.text('222'), findsWidgets);
    expect(find.text('111'), findsNothing);
  });
}
