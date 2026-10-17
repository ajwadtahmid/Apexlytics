import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_time_breakdown_screen.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';

int _allTracked(int i) => 2;

/// The saved window choice, as the app keeps it.
const _windowKey = 'trend_sessions_shown';

/// Pumps [app] with the saved [prefs] behind it, as the app has.
Future<void> pumpScoped(
  WidgetTester tester,
  Widget app, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final saved = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(saved)],
      child: app,
    ),
  );
}

void main() {
  // Newest first, like sessionize(). Early sessions lose RP, recent ones gain.
  final base = DateTime(2026, 9, 1, 20);
  // Each session has 2 games. [tracked] is how many of them (by oldest-first
  // index) reported kills/damage, at 1 kill and 200 damage per reported game.
  List<RankedSession> sessions(
    List<int> netRpOldestFirst, {
    int Function(int i) tracked = _allTracked,
  }) => [
    for (var i = netRpOldestFirst.length - 1; i >= 0; i--)
      RankedSession(
        start: base.add(Duration(days: i)),
        end: base.add(Duration(days: i, hours: 1)),
        games: 2,
        netRp: netRpOldestFirst[i],
        totalKills: tracked(i),
        totalDamage: 200 * tracked(i),
        killsGames: tracked(i),
        damageGames: tracked(i),
        matches: const [],
      ),
  ];

  Future<void> pump(
    WidgetTester tester,
    List<RankedSession> s, {
    Map<String, Object> prefs = const {},
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScoped(
      tester,
      prefs: prefs,
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
      findsNWidgets(3),
    );
    // Top right: previous value, trend icon, new value.
    expect(find.textContaining('-10.0', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    expect(find.byIcon(Icons.trending_flat), findsNWidgets(3));
  });

  testWidgets('says why there is no trend yet with fewer than ten sessions', (
    tester,
  ) async {
    await pump(tester, sessions([10, 20, 30]));
    expect(find.textContaining('Play at least 10 sessions'), findsNWidgets(6));
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

  testWidgets('averages kills and damage over the games that reported them', (
    tester,
  ) async {
    // Same 1 kill / 200 damage per reported game throughout, but only one of
    // the two games reported in the older sessions. Dividing by every game
    // would show that as a doubling.
    await pump(
      tester,
      sessions(List.filled(10, 10), tracked: (i) => i < 5 ? 1 : 2),
    );
    expect(find.textContaining('Improving', findRichText: true), findsNothing);
    expect(
      find.textContaining('Steady: about the same', findRichText: true),
      findsNWidgets(4),
    );
  });

  testWidgets('does not invent a trend when a window has no kills or damage', (
    tester,
  ) async {
    await pump(
      tester,
      sessions(List.filled(10, 10), tracked: (i) => i < 5 ? 0 : 2),
    );
    expect(
      find.textContaining('Not enough games with kills reported'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Not enough games with damage reported'),
      findsOneWidget,
    );
    expect(find.textContaining('Play at least 10 sessions'), findsNothing);
    expect(find.textContaining('Improving', findRichText: true), findsNothing);
  });

  testWidgets('the headers fit a narrow screen with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScoped(
      tester,
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 3000),
            textScaler: TextScaler.linear(1.3),
          ),
          child: RankedTimeBreakdownScreen(
            hourBuckets: const [],
            weekdayBuckets: const [],
            sessions: sessions([for (var i = 0; i < 10; i++) 10]),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('RECENT TREND'), findsOneWidget);
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

  group('the headline', () {
    Finder headline(String text) =>
        find.textContaining(text, findRichText: true);

    testWidgets('says how RP is moving and when the player does best', (
      tester,
    ) async {
      await pump(
        tester,
        sessions([for (var i = 0; i < 10; i++) i < 5 ? -20 : 20]),
      );

      expect(
        headline('Up 20.0 RP per game over your last 5 sessions'),
        findsOneWidget,
      );
      expect(
        headline('You do best on Saturdays, in the evening'),
        findsOneWidget,
      );
    });

    testWidgets('is just the best time when there is no trend yet', (
      tester,
    ) async {
      await pump(tester, sessions([20, 20, 20]));

      expect(headline('You do best on Saturdays'), findsOneWidget);
      expect(headline('over your last'), findsNothing);
    });

    testWidgets('is not there with nothing to say', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpScoped(
        tester,
        const MaterialApp(
          home: RankedTimeBreakdownScreen(hourBuckets: [], weekdayBuckets: []),
        ),
      );

      expect(headline('You do best'), findsNothing);
      expect(headline('over your last'), findsNothing);
    });
  });

  group('a light player', () {
    Future<void> pumpLight(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpScoped(
        tester,
        MaterialApp(
          home: RankedTimeBreakdownScreen(
            hourBuckets: [
              const HourBucket(hourLocal: 19, games: 6, netRp: 60),
              const HourBucket(hourLocal: 9, games: 5, netRp: -25),
            ],
            weekdayBuckets: [
              const WeekdayBucket(weekday: 6, games: 6, netRp: 60),
              const WeekdayBucket(weekday: 1, games: 5, netRp: -25),
            ],
            sessions: sessions([20, 20, 20]),
          ),
        ),
      );
    }

    testWidgets('still gets the best times, as a hint', (tester) async {
      await pumpLight(tester);

      expect(find.text('WHEN YOU PLAY BEST'), findsOneWidget);
      expect(find.text('Saturday'), findsOneWidget);
      expect(
        find.textContaining('Not many games yet, so this uses days and times'),
        findsOneWidget,
      );
      expect(find.textContaining('at least 10 games'), findsNothing);
    });

    testWidgets('a player with enough games gets the usual caption', (
      tester,
    ) async {
      await pump(tester, sessions([20, 20, 20]));

      expect(
        find.textContaining('for days and times with at least 10 games'),
        findsOneWidget,
      );
      expect(find.textContaining('Not many games yet'), findsNothing);
    });
  });

  testWidgets('the hour and day charts have the Games / RP switch', (
    tester,
  ) async {
    await pump(tester, sessions([20, 20, 20]));

    expect(find.text('Performance by Hour'), findsOneWidget);
    expect(find.text('Performance by Day'), findsOneWidget);
    expect(find.text('RP / game'), findsNWidgets(2));
  });

  group('the sessions shown', () {
    // The first LineChart on the page is the RP sparkline.
    LineChartData rp(WidgetTester tester) =>
        tester.widget<LineChart>(find.byType(LineChart).first).data;
    int points(WidgetTester tester) =>
        rp(tester).lineBarsData.first.spots.length;
    Future<void> tapChoice(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pump();
    }

    // The first half lose and the second half gain, 20 RP a session.
    List<RankedSession> many(int n) =>
        sessions([for (var i = 0; i < n; i++) i < n ~/ 2 ? -20 : 20]);
    Finder rich(String text) => find.textContaining(text, findRichText: true);

    testWidgets('offer only the counts there are twice as many sessions for', (
      tester,
    ) async {
      Future<List<String>> offered(int n) async {
        await pump(tester, many(n));
        return [
          for (final label in ['5', '10', '25', '50', 'All'])
            if (find.text(label).evaluate().isNotEmpty) label,
        ];
      }

      // 5 needs 10 sessions, 10 needs 20, 25 needs 50 and 50 needs 100.
      expect(await offered(11), ['5', 'All']);
      expect(await offered(19), ['5', 'All']);
      expect(await offered(20), ['5', '10', 'All']);
      expect(await offered(49), ['5', '10', 'All']);
      expect(await offered(50), ['5', '10', '25', 'All']);
      expect(await offered(100), ['5', '10', '25', '50', 'All']);
    });

    testWidgets('start at five', (tester) async {
      await pump(tester, many(25));

      expect(find.text('Sessions shown'), findsOneWidget);
      expect(points(tester), 5);
      expect(find.textContaining(' · 5 sessions'), findsOneWidget);
    });

    testWidgets('a count sets the headline, the charts and the verdicts', (
      tester,
    ) async {
      await pump(tester, many(25));
      expect(rich('over your last 5 sessions'), findsOneWidget);

      await tapChoice(tester, '10');

      expect(points(tester), 10);
      expect(find.textContaining(' · 10 sessions'), findsOneWidget);
      expect(rich('over your last 10 sessions'), findsOneWidget);
      expect(rich('vs your 10 sessions before'), findsWidgets);
      expect(rich('vs your 5 sessions before'), findsNothing);
    });

    testWidgets('All plots every session and gives the average, not a change', (
      tester,
    ) async {
      await pump(tester, many(25));

      await tapChoice(tester, 'All');

      expect(points(tester), 25);
      expect(find.textContaining(' · 25 sessions'), findsOneWidget);
      // Each session nets +/-20 over 2 games: the average is about 0.
      expect(rich('Averaging'), findsOneWidget);
      expect(rich('over all 25 sessions'), findsWidgets);
      expect(rich('Average over all 25 sessions'), findsNWidgets(4));
      expect(rich('Improving'), findsNothing);
      expect(rich('Declining'), findsNothing);
      expect(find.byIcon(Icons.trending_up), findsNothing);
      expect(find.byIcon(Icons.trending_down), findsNothing);
    });

    testWidgets('the average over all sessions is green when it is a gain', (
      tester,
    ) async {
      await pump(tester, sessions(List.filled(12, 20)), prefs: {_windowKey: 0});

      expect(
        rich('Averaging +10.0 RP per game over all 12 sessions'),
        findsOneWidget,
      );
    });

    testWidgets('are explained in the info sheet, not on the page', (
      tester,
    ) async {
      await pump(tester, many(25));

      // No line of text under the control, and no icon beside it.
      expect(find.textContaining('Sets the headline'), findsNothing);
      expect(find.textContaining('uses every game'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byIcon(Icons.info_outline),
        ),
        findsNothing,
      );
    });

    testWidgets('have no control with too few sessions, and say how many are '
        'needed', (tester) async {
      await pump(tester, many(6));

      expect(find.text('Sessions shown'), findsNothing);
      expect(points(tester), 6);
      expect(
        find.textContaining('Play at least 10 sessions'),
        findsNWidgets(6),
      );
    });

    testWidgets('are kept for next time', (tester) async {
      await pump(tester, many(25));

      await tapChoice(tester, '10');

      final saved = await SharedPreferences.getInstance();
      expect(saved.getInt(_windowKey), 10);
    });

    testWidgets('come back as they were saved', (tester) async {
      await pump(tester, many(25), prefs: {_windowKey: 10});

      expect(points(tester), 10);
    });

    testWidgets('narrow to the biggest count there are sessions for', (
      tester,
    ) async {
      // 50 was saved, but 30 sessions only run to 10 against the 10 before.
      await pump(tester, many(30), prefs: {_windowKey: 50});

      expect(points(tester), 10);
    });

    testWidgets('keep All when it was saved', (tester) async {
      await pump(tester, many(30), prefs: {_windowKey: 0});

      expect(points(tester), 30);
      expect(rich('Average over all 30 sessions'), findsNWidgets(4));
    });

    testWidgets('ignore a saved value that is not one of the counts', (
      tester,
    ) async {
      await pump(tester, many(30), prefs: {_windowKey: 7});

      expect(points(tester), 5);
    });
  });

  group('the smoothed line', () {
    LineChartData rp(WidgetTester tester) =>
        tester.widget<LineChart>(find.byType(LineChart).first).data;

    testWidgets('averages three sessions at a time over the raw one', (
      tester,
    ) async {
      // Per-game RP, oldest first: -10 five times, then +10 five times.
      await pump(
        tester,
        sessions([for (var i = 0; i < 10; i++) i < 5 ? -20 : 20]),
        prefs: {_windowKey: 0}, // every session, so all ten are plotted
      );

      final bars = rp(tester).lineBarsData;
      expect(bars, hasLength(2));
      final smooth = bars.last.spots;
      expect(smooth, hasLength(10));
      expect(smooth[2].y, -10);
      // Sessions 3, 4 and 5 are -10, -10 and +10.
      expect(smooth[5].y, closeTo(-10 / 3, 1e-9));
      expect(smooth.last.y, 10);
    });

    testWidgets('is left out when there are too few sessions to smooth', (
      tester,
    ) async {
      await pump(tester, sessions([10, 20, 30]));

      expect(rp(tester).lineBarsData, hasLength(1));
    });

    testWidgets('says the latest session and the last three averaged', (
      tester,
    ) async {
      await pump(
        tester,
        sessions([for (var i = 0; i < 10; i++) i < 5 ? -20 : 20]),
      );

      expect(
        find.textContaining('Latest session', findRichText: true),
        findsNWidgets(4),
      );
      expect(
        find.textContaining('Last 3 averaged', findRichText: true),
        findsNWidgets(4),
      );
      expect(find.textContaining('+10.0', findRichText: true), findsWidgets);
    });

    testWidgets('has no averaged caption when there is no smoothed line', (
      tester,
    ) async {
      await pump(tester, sessions([10, 20, 30]));

      expect(
        find.textContaining('Latest session', findRichText: true),
        findsNWidgets(4),
      );
      expect(find.textContaining('averaged', findRichText: true), findsNothing);
    });
  });

  group('the sparkline charts', () {
    List<LineChartData> charts(WidgetTester tester) => [
      for (final c in tester.widgetList<LineChart>(find.byType(LineChart)))
        c.data,
    ];

    testWidgets('draw the zero line for RP only, and only when it crosses', (
      tester,
    ) async {
      await pump(
        tester,
        sessions([for (var i = 0; i < 10; i++) i < 5 ? -20 : 20]),
        prefs: {_windowKey: 0}, // every session, so the line crosses zero
      );

      // RP is first; the rest (kills, damage and games per session, here) have
      // nothing to mark.
      final all = charts(tester);
      expect(all.first.extraLinesData.horizontalLines, hasLength(1));
      for (final other in all.skip(1)) {
        expect(other.extraLinesData.horizontalLines, isEmpty);
      }
    });

    testWidgets('an RP line that never crosses zero has no zero line', (
      tester,
    ) async {
      await pump(tester, sessions(List.filled(10, 20)));

      expect(charts(tester).first.extraLinesData.horizontalLines, isEmpty);
    });

    testWidgets('mark each session with a dot only while there are few', (
      tester,
    ) async {
      await pump(tester, sessions(List.filled(25, 10)));
      expect(charts(tester).first.lineBarsData.first.dotData.show, isTrue);

      await tester.tap(find.text('All'));
      await tester.pump();
      expect(charts(tester).first.lineBarsData.first.dotData.show, isFalse);
    });
  });

  group('win rate, game length and games per session', () {
    // Oldest first: [wins, losses, seconds a game ran, games] for each session.
    List<RankedSession> played(
      List<({int wins, int losses, int secs, int games})> oldestFirst,
    ) => [
      for (var i = oldestFirst.length - 1; i >= 0; i--)
        RankedSession(
          start: DateTime(2026, 9, 1 + i, 20),
          end: DateTime(2026, 9, 1 + i, 21),
          games: oldestFirst[i].games,
          netRp: 10,
          totalKills: 0,
          totalDamage: 0,
          killsGames: 0,
          damageGames: 0,
          wins: oldestFirst[i].wins,
          losses: oldestFirst[i].losses,
          totalLengthSecs: oldestFirst[i].secs * oldestFirst[i].games,
          matches: const [],
        ),
    ];

    ({int wins, int losses, int secs, int games}) s(
      int wins,
      int losses, {
      int secs = 600,
      int games = 4,
    }) => (wins: wins, losses: losses, secs: secs, games: games);

    Finder rich(String text) => find.textContaining(text, findRichText: true);

    List<LineChartData> charts(WidgetTester tester) => [
      for (final c in tester.widgetList<LineChart>(find.byType(LineChart)))
        c.data,
    ];

    testWidgets('are rows of the trend card, after RP and win rate', (
      tester,
    ) async {
      await pump(tester, played([for (var i = 0; i < 10; i++) s(2, 2)]));

      for (final label in [
        'RP per game',
        'Win rate',
        'Kills per game',
        'Damage per game',
        'Game length',
        'Games per session',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      final win = tester.getTopLeft(find.text('Win rate')).dy;
      expect(tester.getTopLeft(find.text('RP per game')).dy, lessThan(win));
      expect(win, lessThan(tester.getTopLeft(find.text('Kills per game')).dy));
      expect(
        tester.getTopLeft(find.text('Game length')).dy,
        lessThan(tester.getTopLeft(find.text('Games per session')).dy),
      );
    });

    testWidgets('win rate says how many points it moved, and is improving', (
      tester,
    ) async {
      // 1 win in 4 games, then 3 in 4: from 25% to 75%.
      await pump(
        tester,
        played([for (var i = 0; i < 10; i++) i < 5 ? s(1, 3) : s(3, 1)]),
      );

      expect(
        rich('Improving: +50.0 pts win rate vs your 5 sessions before'),
        findsOneWidget,
      );
      expect(rich('25%'), findsWidgets);
      expect(rich('75%'), findsWidgets);
    });

    testWidgets('a falling win rate is declining', (tester) async {
      await pump(
        tester,
        played([for (var i = 0; i < 10; i++) i < 5 ? s(3, 1) : s(2, 2)]),
      );

      expect(
        rich('Declining: -25.0 pts win rate vs your 5 sessions before'),
        findsOneWidget,
      );
    });

    testWidgets('win rate marks half, when the chart crosses it', (
      tester,
    ) async {
      await pump(
        tester,
        played([for (var i = 0; i < 10; i++) i < 5 ? s(1, 3) : s(3, 1)]),
        prefs: {_windowKey: 0}, // every session, so it runs 25% to 75%
      );

      // These sessions have no kills or damage, so those draw no chart: RP, win
      // rate, game length and games per session are what is left.
      final all = charts(tester);
      expect(all, hasLength(4));
      expect(all[1].extraLinesData.horizontalLines.single.y, 0.5);
      // Nothing else is marked: RP never crosses 0 here, the others have none.
      expect(all[0].extraLinesData.horizontalLines, isEmpty);
      expect(all[2].extraLinesData.horizontalLines, isEmpty);
      expect(all[3].extraLinesData.horizontalLines, isEmpty);
    });

    testWidgets('a win rate that stays on one side of half has no line', (
      tester,
    ) async {
      await pump(tester, played([for (var i = 0; i < 10; i++) s(3, 1)]));

      expect(charts(tester)[1].extraLinesData.horizontalLines, isEmpty);
    });

    testWidgets('game length says up or down, in minutes and seconds', (
      tester,
    ) async {
      // Games of 10 minutes, then of 15.
      await pump(
        tester,
        played([for (var i = 0; i < 10; i++) s(2, 2, secs: i < 5 ? 600 : 900)]),
      );

      expect(
        rich('Up: +5m 00s game length vs your 5 sessions before'),
        findsOneWidget,
      );
      expect(rich('10m 00s'), findsWidgets);
      expect(rich('15m 00s'), findsWidgets);
      // It isn't improving, which would call a longer game good.
      expect(rich('Improving: +5m'), findsNothing);
    });

    testWidgets('shorter games are down', (tester) async {
      await pump(
        tester,
        played([for (var i = 0; i < 10; i++) s(2, 2, secs: i < 5 ? 930 : 600)]),
      );

      expect(
        rich('Down: -5m 30s game length vs your 5 sessions before'),
        findsOneWidget,
      );
      expect(rich('Declining: -5m'), findsNothing);
    });

    testWidgets('games per session says up or down', (tester) async {
      // 2 games a session, then 5.
      await pump(
        tester,
        played([for (var i = 0; i < 10; i++) s(1, 1, games: i < 5 ? 2 : 5)]),
      );

      expect(
        rich('Up: +3.0 games per session vs your 5 sessions before'),
        findsOneWidget,
      );
      expect(rich('2.0'), findsWidgets);
      expect(rich('5.0'), findsWidgets);
    });

    testWidgets('a steady length or session size says steady', (tester) async {
      await pump(tester, played([for (var i = 0; i < 10; i++) s(2, 2)]));

      // RP, win rate, game length and games per session; kills and damage have
      // no readings here, so they say nothing.
      expect(
        rich('Steady: about the same as your 5 sessions before'),
        findsNWidgets(4),
      );
    });

    testWidgets('the neutral rows never say improving or declining', (
      tester,
    ) async {
      await pump(
        tester,
        played([
          for (var i = 0; i < 10; i++)
            s(2, 2, secs: i < 5 ? 600 : 900, games: i < 5 ? 2 : 5),
        ]),
      );

      expect(rich('Up: '), findsNWidgets(2));
      expect(rich('Improving'), findsNothing);
    });

    testWidgets('over every session, give the average of each', (tester) async {
      await pump(
        tester,
        played([for (var i = 0; i < 10; i++) s(3, 1)]),
        prefs: {_windowKey: 0},
      );

      expect(
        rich('Average over all 10 sessions: 75% win rate'),
        findsOneWidget,
      );
      expect(
        rich('Average over all 10 sessions: 10m 00s game length'),
        findsOneWidget,
      );
      expect(
        rich('Average over all 10 sessions: 4.0 games per session'),
        findsOneWidget,
      );
    });

    testWidgets('say so when no game has a result or a length', (tester) async {
      // Sessions built without matches carry none.
      await pump(tester, sessions([for (var i = 0; i < 10; i++) 10]));

      expect(
        rich('Not enough games with results reported to show a trend'),
        findsOneWidget,
      );
      expect(
        rich('Not enough games with lengths reported to show a trend'),
        findsOneWidget,
      );
    });
  });

  group('the info button', () {
    Finder button() => find.byTooltip('How to read this');

    testWidgets('is in the app bar and opens a sheet saying how to read it', (
      tester,
    ) async {
      await pump(tester, sessions(List.filled(25, 10)));
      expect(button(), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: button()),
        findsOneWidget,
      );
      expect(find.textContaining('whichever count is chosen'), findsNothing);

      await tester.tap(button());
      await tester.pumpAndSettle();

      expect(find.text('Performance Trends'), findsWidgets);
      expect(
        find.textContaining('Sessions shown sets the headline and the trends'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'hour and day charts use every game in this period',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('averages every session with'),
        findsOneWidget,
      );
      expect(find.textContaining('up or down'), findsOneWidget);
      expect(find.textContaining('under 3 games are faded'), findsOneWidget);
      expect(find.textContaining('need 10 games (or 5'), findsOneWidget);
    });

    testWidgets('is there with too few sessions for a control too', (
      tester,
    ) async {
      await pump(tester, sessions([10, 20, 30]));

      expect(find.text('Sessions shown'), findsNothing);
      expect(button(), findsOneWidget);
    });
  });
}
