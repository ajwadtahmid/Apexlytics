import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_session_detail_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_sessions_list_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_sessions_screen.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// Sessions of the given games' RP, oldest first, hours apart.
List<RankedSession> _sessions(List<List<int>> plan) {
  final matches = <RankedMatch>[];
  var at = 1782000000;
  for (final rps in plan) {
    for (final rp in rps) {
      matches.add(buildMatch(rp: rp, start: at));
      at += 1500;
    }
    at += 5 * 3600;
  }
  return sessionize(matches);
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<RankedSession> sessions, {
    Size size = const Size(800, 2400),
    DateTime? now,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: RankedSessionsListScreen(
            sessions: sessions,
            onRefresh: () async {},
            now: now,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // Played: +30 over two games, -30 over three, then +5 over one.
  final three = _sessions([
    [20, 10],
    [-15, -5, -10],
    [5],
  ]);

  Finder rich(String text) => find.textContaining(text, findRichText: true);

  group('the overview', () {
    testWidgets('adds the sessions up', (tester) async {
      await pump(tester, three);

      expect(find.text('sessions'), findsOneWidget);
      expect(find.text('2.0'), findsOneWidget); // games each
      expect(find.text('+1.7'), findsOneWidget); // RP each: 5 over 3
    });

    testWidgets('names the best and worst session, and marks them', (
      tester,
    ) async {
      await pump(tester, three);

      expect(rich('Best session'), findsOneWidget);
      expect(rich('Worst session'), findsOneWidget);
      expect(find.text('BEST'), findsOneWidget);
      expect(find.text('WORST'), findsOneWidget);
    });

    testWidgets('charts a bar for each session', (tester) async {
      await pump(tester, three);

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      // Oldest first: +30, -30, +5.
      expect(chart.data.barGroups.map((g) => g.barRods.single.toY), [
        30,
        -30,
        5,
      ]);
    });

    testWidgets('a single session has no best or worst and no chart', (
      tester,
    ) async {
      await pump(
        tester,
        _sessions([
          [20, 10],
        ]),
      );

      expect(rich('Worst session'), findsNothing);
      expect(find.text('BEST'), findsNothing);
      expect(find.text('WORST'), findsNothing);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('tapping the best session opens it, games and all', (
      tester,
    ) async {
      await pump(tester, three);

      await tester.tap(rich('Best session'));
      await tester.pumpAndSettle();

      expect(find.byType(RankedSessionDetailScreen), findsOneWidget);
      expect(find.text('GAMES · 2'), findsOneWidget);
    });

    testWidgets('tapping a bar opens that session', (tester) async {
      await pump(tester, three);

      final bar = tester.getTopLeft(find.byType(BarChart));
      // The first bar is the oldest session, +30 RP over two games.
      await tester.tapAt(bar + const Offset(123, 20));
      await tester.pumpAndSettle();

      expect(find.byType(RankedSessionDetailScreen), findsOneWidget);
    });
  });

  group('the headings', () {
    // Local dates, so the headings don't depend on the time zone.
    List<RankedSession> at(List<(DateTime, int)> plan) => sessionize([
      for (final (day, rp) in plan)
        buildMatch(rp: rp, start: day.millisecondsSinceEpoch ~/ 1000),
    ]);
    final now = DateTime(2026, 10, 14, 15);

    testWidgets('sort the sessions under when they were played', (
      tester,
    ) async {
      await pump(
        tester,
        at([
          (DateTime(2026, 10, 14, 10), 30),
          (DateTime(2026, 10, 13, 20), -10),
          (DateTime(2026, 9, 1, 20), 5),
        ]),
        now: now,
      );

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text('SEPTEMBER 2026'), findsOneWidget);
      expect(find.text('RECENT SESSIONS'), findsNothing);
    });

    testWidgets('say how many sessions each holds and what they netted', (
      tester,
    ) async {
      await pump(
        tester,
        at([
          (DateTime(2026, 10, 14, 18), 30),
          (DateTime(2026, 10, 14, 9), -10),
          (DateTime(2026, 10, 13, 20), 5),
        ]),
        now: now,
      );

      expect(find.text('2 sessions · '), findsOneWidget);
      expect(find.text('1 session · '), findsOneWidget);
      // Today nets +20 and the day before +5.
      expect(find.text('+20 RP'), findsWidgets);
    });

    testWidgets('a heading comes before its sessions', (tester) async {
      await pump(
        tester,
        at([
          (DateTime(2026, 10, 14, 10), 30),
          (DateTime(2026, 10, 13, 20), -10),
        ]),
        now: now,
      );

      final today = tester.getTopLeft(find.text('TODAY')).dy;
      final yesterday = tester.getTopLeft(find.text('YESTERDAY')).dy;
      final firstTile = tester
          .getTopLeft(find.byType(SessionRecapTile).first)
          .dy;
      expect(today, lessThan(firstTile));
      expect(firstTile, lessThan(yesterday));
    });
  });

  group('a session\'s tile', () {
    testWidgets('shows how each game went and the RP through it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        _sessions([
          [20, -10, 15],
        ]),
      );

      // Read out with the rest of the tile.
      expect(find.bySemanticsLabel(RegExp('2 wins, 1 loss')), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a single game has its one segment but no line', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        _sessions([
          [20],
        ]),
      );

      expect(find.bySemanticsLabel(RegExp('1 win, 0 losses')), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      handle.dispose();
    });
  });

  group('scrolling the list', () {
    // Forty sessions; the oldest has seven games and the rest two.
    final many = _sessions([
      [10, 10, 10, 10, 10, 10, 10],
      for (var i = 0; i < 39; i++) [i.isEven ? 10 : -10, 5],
    ]);

    testWidgets('has no Load more button', (tester) async {
      await pump(tester, many);

      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('builds the cards as they come into view, down to the oldest', (
      tester,
    ) async {
      await pump(tester, many, size: const Size(400, 900));
      final oldest = find.byWidgetPredicate(
        (w) => w is SessionRecapTile && w.session.games == 7,
      );

      // Not built yet, far below the screen.
      expect(find.byType(SessionRecapTile).evaluate().length, lessThan(40));
      expect(oldest, findsNothing);

      await tester.scrollUntilVisible(
        oldest,
        400,
        scrollable: find.byType(Scrollable).first,
      );

      expect(oldest, findsOneWidget);
    });
  });
}
