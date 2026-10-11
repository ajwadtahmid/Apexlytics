import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_stats_card.dart';
import 'package:apexlytics/utils/formatting/format.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';

void main() {
  RankedMatch game(int i, {required bool tracked}) => RankedMatch.fromJson({
    'uid': '1',
    'name': 'Tester',
    'legendPlayed': 'Axle',
    'gameMode': 'BATTLE_ROYALE',
    'gameLengthSecs': 600,
    'gameStartTimestamp': 1782090000 + i * 3600,
    'gameEndTimestamp': 1782090000 + i * 3600 + 600,
    'gameData': [
      if (tracked) ...[
        {'key': 'kills', 'value': 4, 'name': 'BR Kills'},
        {'key': 'damage', 'value': 800, 'name': 'BR Damage'},
      ],
    ],
    'BRScoreChange': 10,
    'BRScore': 1000 + i,
    'map': 'olympus_rotation',
  });

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
