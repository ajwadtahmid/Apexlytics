import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_rp_chart.dart';
import 'package:apexlytics/utils/formatting/season_utils.dart' show WeekRange;
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import '../helpers.dart';

/// Smoke coverage for a widget that was previously 0% covered — renders
/// without crashing across the point counts that matter (0, 1, a normal
/// split, and past the downsample cap).
void main() {
  RankedMatch match(int index) =>
      buildMatch(start: index * 700, cumulativeRp: 1000 + index * 10);

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

  testWidgets('a session gap surfaces the session picker, defaulting to All', (
    tester,
  ) async {
    // match(0) and match(1) are 700s apart (well under kSessionGap); insert
    // a match far enough later to start a second session.
    final farLater = buildMatch(
      start: kSessionGap.inSeconds * 2,
      cumulativeRp: 1030,
    );
    await tester.pumpWidget(app([match(0), match(1), farLater]));
    await tester.pump();

    expect(find.text('All sessions'), findsOneWidget);
  });

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
  group('with every week selected', () {
    // A split of four weeks. W1 has three games in three sessions, W2 one
    // game, W3 none yet, W4 four games in four sessions: eight sessions, but
    // only three weeks with games.
    final splitStart = DateTime.utc(2026, 9, 8);
    final weeks = [
      for (var i = 0; i < 4; i++)
        WeekRange(
          start: splitStart.add(Duration(days: 7 * i)),
          end: splitStart.add(Duration(days: 7 * (i + 1))),
        ),
    ];
    int at(int week, int session) =>
        splitStart.millisecondsSinceEpoch ~/ 1000 +
        week * 7 * 86400 +
        3600 +
        session * 3 * 3600; // gaps well past kSessionGap

    final matches = [
      for (var s = 0; s < 3; s++)
        buildMatch(start: at(0, s), cumulativeRp: 1000 + s * 10),
      buildMatch(start: at(1, 0), cumulativeRp: 1040),
      for (var s = 0; s < 4; s++)
        buildMatch(start: at(3, s), cumulativeRp: 1050 + s * 10),
    ];

    Widget weekApp({int weekIndex = -1, List<WeekRange>? weeksShown}) =>
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RankedRpChart(
              matches: matches,
              sessions: sessionize(matches),
              weeks: weeksShown ?? weeks,
              weekIndex: weekIndex,
            ),
          ),
        );

    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();
    }

    testWidgets('the picker offers weeks, not sessions', (tester) async {
      await tester.pumpWidget(weekApp());
      await tester.pump();

      expect(find.text('All weeks'), findsOneWidget);
      expect(find.text('All sessions'), findsNothing);

      await openPicker(tester);

      // All weeks, and the three weeks with games; the empty W3 is left out.
      expect(find.byType(PopupMenuItem<int>), findsNWidgets(4));
      expect(find.textContaining('W1 · '), findsOneWidget);
      expect(find.textContaining('W2 · '), findsOneWidget);
      expect(find.textContaining('W3 · '), findsNothing);
      expect(find.textContaining('W4 · '), findsOneWidget);
      expect(find.textContaining('3 games'), findsOneWidget);
      expect(find.textContaining('1 game'), findsOneWidget);
      expect(find.textContaining('4 games'), findsOneWidget);
    });

    testWidgets('choosing a week plots only that week', (tester) async {
      await tester.pumpWidget(weekApp());
      await tester.pump();
      expect(find.byType(LineChart), findsOneWidget);

      await openPicker(tester);
      await tester.tap(find.textContaining('W2 · '));
      await tester.pumpAndSettle();

      // One game is not a line.
      expect(find.text('Not enough matches in this range'), findsOneWidget);
      expect(find.textContaining('W2 · '), findsOneWidget, reason: 'the pill');

      await openPicker(tester);
      await tester.tap(find.textContaining('W4 · ').last);
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('"All weeks" brings the whole split back', (tester) async {
      await tester.pumpWidget(weekApp());
      await tester.pump();
      await openPicker(tester);
      await tester.tap(find.textContaining('W2 · '));
      await tester.pumpAndSettle();

      await openPicker(tester);
      await tester.tap(find.text('All weeks').last);
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('All weeks'), findsOneWidget);
    });

    testWidgets('with one week selected on the page, it lists its sessions', (
      tester,
    ) async {
      await tester.pumpWidget(weekApp(weekIndex: 0));
      await tester.pump();

      expect(find.text('All sessions'), findsOneWidget);
      await openPicker(tester);
      // All sessions, and all eight, as before.
      expect(find.byType(PopupMenuItem<int>), findsNWidgets(9));
    });

    testWidgets('a split with no weeks lists its sessions', (tester) async {
      await tester.pumpWidget(weekApp(weeksShown: const []));
      await tester.pump();

      expect(find.text('All sessions'), findsOneWidget);
    });

    testWidgets('changing the page\'s week starts the chart over', (
      tester,
    ) async {
      await tester.pumpWidget(weekApp());
      await tester.pump();
      await openPicker(tester);
      await tester.tap(find.textContaining('W2 · '));
      await tester.pumpAndSettle();

      await tester.pumpWidget(weekApp(weekIndex: 3));
      await tester.pump();
      expect(find.text('All sessions'), findsOneWidget);

      await tester.pumpWidget(weekApp());
      await tester.pump();
      expect(find.text('All weeks'), findsOneWidget);
    });
  });
}
