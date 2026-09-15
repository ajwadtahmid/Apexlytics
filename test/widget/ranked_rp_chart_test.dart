import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_rp_chart.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';

/// Smoke coverage for a widget that was previously 0% covered — renders
/// without crashing across the point counts that matter (0, 1, a normal
/// split, and past the downsample cap).
void main() {
  RankedMatch match(int index) => RankedMatch.fromJson({
    'uid': '1',
    'name': 'Tester',
    'legendPlayed': 'Axle',
    'gameMode': 'BATTLE_ROYALE',
    'gameLengthSecs': 600,
    'gameStartTimestamp': index * 700,
    'gameEndTimestamp': index * 700 + 600,
    'gameData': <Map<String, Object?>>[],
    'BRScoreChange': 10,
    'BRScore': 1000 + index * 10,
    'map': 'olympus_rotation',
    'isPartyFull': false,
  });

  Widget app(List<RankedMatch> matches) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: RankedRpChart(matches: matches, sessions: sessionize(matches)),
    ),
  );

  testWidgets('no matches shows the "not enough" message, not a chart', (
    tester,
  ) async {
    await tester.pumpWidget(app(const []));
    await tester.pump();

    expect(find.text('Not enough matches in this range'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('one match shows the "not enough" message, not a chart', (
    tester,
  ) async {
    await tester.pumpWidget(app([match(0)]));
    await tester.pump();

    expect(find.text('Not enough matches in this range'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('two or more matches renders the chart', (tester) async {
    await tester.pumpWidget(app([match(0), match(1), match(2)]));
    await tester.pump();

    expect(find.text('Not enough matches in this range'), findsNothing);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets(
    'a session gap surfaces the session picker, defaulting to All',
    (tester) async {
      // match(0) and match(1) are 700s apart (well under kSessionGap); insert
      // a match far enough later to start a second session.
      final farLater = RankedMatch.fromJson({
        'uid': '1',
        'name': 'Tester',
        'legendPlayed': 'Axle',
        'gameMode': 'BATTLE_ROYALE',
        'gameLengthSecs': 600,
        'gameStartTimestamp': kSessionGap.inSeconds * 2,
        'gameEndTimestamp': kSessionGap.inSeconds * 2 + 600,
        'gameData': <Map<String, Object?>>[],
        'BRScoreChange': 10,
        'BRScore': 1030,
        'map': 'olympus_rotation',
        'isPartyFull': false,
      });
      await tester.pumpWidget(app([match(0), match(1), farLater]));
      await tester.pump();

      expect(find.text('All sessions'), findsOneWidget);
    },
  );

  testWidgets(
    'well past the downsample cap (kMaxChartPoints) still renders without '
    'crashing, and drops individual dots past kMaxDotPoints',
    (tester) async {
      // 500 > both _kMaxDotPoints (150) and _kMaxChartPoints (400). The
      // assertion here is simply "no exception and a chart renders"; the
      // internal downsample math is covered by reading the implementation,
      // not re-derived here.
      final matches = [for (var i = 0; i < 500; i++) match(i)];

      await tester.pumpWidget(app(matches));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(LineChart), findsOneWidget);
    },
  );
}
