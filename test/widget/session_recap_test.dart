import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_sessions_screen.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/widgets/rp_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

void main() {
  RankedSession session({required int killsGames}) => RankedSession(
    start: DateTime(2026, 9, 1, 20),
    end: DateTime(2026, 9, 1, 21),
    games: 3,
    netRp: 20,
    totalKills: killsGames * 2,
    totalDamage: 0,
    killsGames: killsGames,
    damageGames: 0,
    matches: const [],
  );

  Future<void> pump(WidgetTester tester, RankedSession s) async =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [await prefsOverride()],
          child: MaterialApp(
            home: Scaffold(body: SessionRecapBody(session: s)),
          ),
        ),
      );

  testWidgets('kills show no reading when no game reported them', (
    tester,
  ) async {
    await pump(tester, session(killsGames: 0));

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('kills show the total when some games reported them', (
    tester,
  ) async {
    await pump(tester, session(killsGames: 2));

    expect(find.text('4'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('shows no time played, which is on the session page', (
    tester,
  ) async {
    await pump(tester, session(killsGames: 2));

    expect(find.text('played'), findsNothing);
    expect(find.text('games'), findsOneWidget);
    expect(find.text('kills'), findsOneWidget);
  });

  testWidgets('a long legend name stops short of the RP column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final played = sessionize([
      for (var i = 0; i < 4; i++)
        buildMatch(
          legend: 'Mad Maggie',
          rp: i.isEven ? 25 : -12,
          start: 1782090000 + i * 1500,
        ),
    ]).single;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [await prefsOverride()],
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(32),
              child: SessionRecapBody(session: played),
            ),
          ),
        ),
      ),
    );

    final name = tester.getTopRight(find.text('Mad Maggie')).dx;
    final pill = tester.getTopLeft(find.byType(RpPill)).dx;
    expect(name, lessThanOrEqualTo(pill));
  });

  testWidgets('the top legend follows the "rank by" choice', (tester) async {
    // Wraith earns more a game, Octane more in all; one session.
    final s = sessionize([
      for (var i = 0; i < 3; i++)
        buildMatch(legend: 'Wraith', rp: 10, start: 1782090000 + i * 1500),
      for (var i = 0; i < 10; i++)
        buildMatch(legend: 'Octane', rp: 4, start: 1782090000 + (3 + i) * 1500),
    ]).single;

    for (final (saved, top, other) in [
      // Total RP, until another is chosen: Octane has earned the most.
      (<String, Object>{}, 'Octane', 'Wraith'),
      (<String, Object>{'best_metric': 'rpPerGame'}, 'Wraith', 'Octane'),
    ]) {
      SharedPreferences.setMockInitialValues(saved);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Scaffold(body: SessionRecapBody(session: s)),
          ),
        ),
      );

      expect(find.text(top), findsOneWidget, reason: '$saved');
      expect(find.text(other), findsNothing, reason: '$saved');
    }
  });

  group('the strip of results', () {
    RankedSession played(List<int> rps) => sessionize([
      for (final (i, rp) in rps.indexed)
        buildMatch(rp: rp, start: 1782090000 + i * 1500),
    ]).single;

    testWidgets('a one-game session has one segment', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, played([25]));

      expect(find.bySemanticsLabel(RegExp('1 win, 0 losses')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a lost one-game session has one red segment', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, played([-14]));

      expect(find.bySemanticsLabel(RegExp('0 wins, 1 loss')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a session with no games has no strip', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, session(killsGames: 1));

      expect(find.bySemanticsLabel(RegExp('wins')), findsNothing);
      handle.dispose();
    });
  });

  testWidgets('games, kills and top legend are spread evenly across the row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final played = sessionize([
      for (var i = 0; i < 4; i++)
        buildMatch(rp: 10, kills: 2, start: 1782090000 + i * 1500),
    ]).single;
    await pump(tester, played);

    final games = tester.getRect(find.text('games'));
    final kills = tester.getRect(find.text('kills'));
    final legend = tester.getRect(find.text('top legend'));
    final firstGap = kills.left - games.right;
    final secondGap = legend.left - kills.right;
    expect(firstGap, greaterThan(0));
    expect(firstGap, closeTo(secondGap, 0.5));
  });
}
