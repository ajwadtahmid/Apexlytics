import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_stats_card.dart';
import 'package:apexlytics/utils/formatting/format.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import '../helpers.dart';

void main() {
  RankedMatch game(int i, {required bool tracked}) => buildMatch(
    start: 1782090000 + i * 3600,
    cumulativeRp: 1000 + i,
    kills: tracked ? 4 : null,
    damage: tracked ? 800 : null,
  );

  Future<void> pump(WidgetTester tester, List<RankedMatch> games) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RankedStatsCard(summary: summarize(rankedOnly(games))),
          ),
        ),
      );

  testWidgets('shows a dash, not zeros, when no game reported kills or damage', (
    tester,
  ) async {
    await pump(tester, [for (var i = 0; i < 3; i++) game(i, tracked: false)]);

    // Average and total, for both kills and damage.
    expect(find.text(kNoReading), findsNWidgets(4));
    expect(find.text('0.0'), findsNothing);
  });

  testWidgets('shows the figures once games reported them', (tester) async {
    await pump(tester, [for (var i = 0; i < 3; i++) game(i, tracked: true)]);

    expect(find.text(kNoReading), findsNothing);
    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('800'), findsOneWidget);
  });
}
