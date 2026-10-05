import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/screens/ranked/ranked_time_breakdown_screen.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';

void main() {
  // Newest first, like sessionize(). Early sessions lose RP, recent ones gain.
  final base = DateTime(2026, 9, 1, 20);
  List<RankedSession> sessions(List<int> netRpOldestFirst) => [
    for (var i = netRpOldestFirst.length - 1; i >= 0; i--)
      RankedSession(
        start: base.add(Duration(days: i)),
        end: base.add(Duration(days: i, hours: 1)),
        games: 2,
        netRp: netRpOldestFirst[i],
        totalKills: 2,
        totalDamage: 400,
        matches: const [],
      ),
  ];

  Future<void> pump(WidgetTester tester, List<RankedSession> s) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RankedTimeBreakdownScreen(
          hourBuckets: [
            for (final h in [9, 19, 20])
              HourBucket(hourLocal: h, games: 12, netRp: h == 9 ? -36 : 60),
          ],
          weekdayBuckets: [
            const WeekdayBucket(weekday: 6, games: 14, netRp: 70),
            const WeekdayBucket(weekday: 1, games: 12, netRp: -24),
          ],
          sessions: s,
        ),
      ),
    );
  }

  testWidgets('spells out whether each stat is improving or declining', (
    tester,
  ) async {
    await pump(
      tester,
      sessions([for (var i = 0; i < 10; i++) i < 5 ? -20 : 20]),
    );

    expect(find.text('RP per game'), findsOneWidget);
    expect(find.text('Kills per game'), findsOneWidget);
    expect(find.text('Damage per game'), findsOneWidget);
    // RP went from -10/game to +10/game; kills and damage did not move.
    expect(
      find.textContaining(
        'Improving: +20.0 RP per game vs your 5 sessions before',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Steady: about the same as your 5 sessions before',
        findRichText: true,
      ),
      findsNWidgets(2),
    );
    // Top right: previous value, trend icon, new value.
    expect(find.textContaining('-10.0', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    expect(find.byIcon(Icons.trending_flat), findsNWidgets(2));
  });

  testWidgets('says why there is no trend yet with fewer than ten sessions', (
    tester,
  ) async {
    await pump(tester, sessions([10, 20, 30]));
    expect(find.textContaining('Play at least 10 sessions'), findsNWidgets(3));
    expect(find.textContaining('Improving'), findsNothing);
  });

  testWidgets('names the best and toughest time to play', (tester) async {
    await pump(tester, sessions([10, 20, 30]));
    expect(find.text('WHEN YOU PLAY BEST'), findsOneWidget);
    expect(find.text('Saturday'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Evening (5 – 10 PM)'), findsOneWidget);
    expect(find.text('Morning (5 AM – 12 PM)'), findsOneWidget);
  });

  testWidgets('says when an improving RP trend is still a loss', (
    tester,
  ) async {
    // -25 per game, then -10 per game.
    await pump(
      tester,
      sessions([for (var i = 0; i < 10; i++) i < 5 ? -50 : -20]),
    );
    expect(
      find.textContaining(
        'Improving: +15.0 RP per game vs your 5 sessions before, '
        'still losing RP',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('says when a declining RP trend is still a gain', (tester) async {
    // +30 per game, then +15 per game.
    await pump(
      tester,
      sessions([for (var i = 0; i < 10; i++) i < 5 ? 60 : 30]),
    );
    expect(
      find.textContaining(
        'Declining: -15.0 RP per game vs your 5 sessions before, '
        'still gaining RP',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });
}
