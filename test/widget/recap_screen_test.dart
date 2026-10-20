import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_recap_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_recap_share_screen.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_share_cards.dart';
import 'package:apexlytics/screens/ranked/widgets/recap_journey_chart.dart';
import 'package:apexlytics/utils/share_image.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/rank_badge.dart';
import 'package:apexlytics/widgets/stat_display.dart' show StatGrid;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

void main() {
  setUp(() => debugCanShareFiles = true);
  tearDown(() => debugCanShareFiles = null);

  final t0 = 1782090000;

  // Four wins on one legend and map, +20 each with two kills.
  final wins = [
    for (var i = 0; i < 4; i++)
      buildMatch(
        start: t0 + i * 1500,
        rp: 20,
        cumulativeRp: 1020 + i * 20,
        kills: 2,
        damage: 400,
      ),
  ];

  // Up 40, down 30, up 20: the peak is part way through.
  List<RankedMatch> upAndDown() {
    var rp = 1000;
    return [
      for (final (i, d) in [20, 20, -15, -15, 10, 10].indexed)
        buildMatch(start: t0 + i * 1500, rp: d, cumulativeRp: rp += d),
    ];
  }

  Future<void> pump(
    WidgetTester tester,
    List<RankedMatch> matches, {
    bool isPredator = false,
    String periodPhrase = 'this split',
    Map<String, Object> saved = const {},
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: RankedRecapScreen(
            matches: matches,
            scope: 'S30 Split 2',
            playerName: 'Reptar',
            isPredator: isPredator,
            periodPhrase: periodPhrase,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('leads with where the player ended up', (tester) async {
    await pump(tester, wins);

    expect(find.text('Recap'), findsOneWidget);
    expect(find.text('1,080 RP'), findsOneWidget);
    expect(find.text('+80 RP this split'), findsOneWidget);
    expect(find.text('S30 Split 2'), findsOneWidget);
  });

  testWidgets('says week when a single week is on screen', (tester) async {
    await pump(tester, wins, periodPhrase: 'in Week 4');

    expect(find.text('+80 RP in Week 4'), findsOneWidget);
    expect(find.textContaining('this split'), findsNothing);
  });

  testWidgets('says RP and split, never period', (tester) async {
    await pump(tester, wins);

    expect(find.textContaining('this period'), findsNothing);
  });

  group('the climb', () {
    testWidgets('is drawn from where the player started to where they ended', (
      tester,
    ) async {
      await pump(tester, wins);

      expect(find.text('Your climb'), findsOneWidget);
      expect(find.byType(RecapJourneyChart), findsOneWidget);
      // Four wins of +20 from 1,000.
      expect(find.text('Start '), findsOneWidget);
      expect(find.text('1,000'), findsOneWidget);
      expect(find.text('Finish '), findsOneWidget);
      expect(find.text('1,080'), findsWidgets);
    });

    testWidgets('names the peak when it was part way through', (tester) async {
      await pump(tester, upAndDown());

      expect(find.text('Peak '), findsOneWidget);
      // 1,000 + 20 + 20.
      expect(find.text('1,040'), findsWidgets);
    });

    testWidgets('does not name a peak that is the finish', (tester) async {
      await pump(tester, wins);

      expect(find.text('Peak '), findsNothing);
    });

    testWidgets('copes with a single game', (tester) async {
      await pump(tester, [
        buildMatch(start: t0, rp: 20, cumulativeRp: 1020, kills: 1),
      ]);

      expect(find.byType(RecapJourneyChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('lays the figures out as the card does, two to a row', (
    tester,
  ) async {
    await pump(tester, wins);

    final rows = [
      ['Games', 'Peak RP'],
      ['Kills', 'Damage'],
      ['Best session', 'Time played'],
      ['Best legend', 'Best map'],
      ['Win rate', 'RP per game'],
    ];
    // The "Rank by" pill above the grid names a figure too ("RP per game").
    Finder figure(String label) =>
        find.descendant(of: find.byType(StatGrid), matching: find.text(label));
    double? previousTop;
    for (final row in rows) {
      final left = tester.getTopLeft(figure(row[0]));
      final right = tester.getTopLeft(figure(row[1]));
      expect(left.dy, right.dy, reason: '$row share a row');
      expect(left.dx, lessThan(right.dx), reason: '$row in order');
      if (previousTop != null) expect(left.dy, greaterThan(previousTop));
      previousTop = left.dy;
    }
  });

  group('what "best" means', () {
    testWidgets('is Total RP, said under the best legend and map', (
      tester,
    ) async {
      await pump(tester, wins);

      expect(find.text('Rank by:'), findsOneWidget);
      // The legend's and the map's figure, as the same measure; the best
      // session says its own.
      expect(find.text('+80 RP'), findsNWidgets(3));
      expect(find.text('+20.0 /game'), findsNothing);
    });

    testWidgets('follows the saved choice', (tester) async {
      await pump(tester, wins, saved: {'best_metric': 'totalKills'});

      expect(find.text('Total kills'), findsOneWidget); // the pill
      expect(find.text('8 kills'), findsNWidgets(2));
      expect(find.text('+20.0 /game'), findsNothing);
    });

    testWidgets('can be changed from the recap itself', (tester) async {
      await pump(tester, wins);

      await tester.tap(find.text('Total RP').first); // the pill
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avg RP'));
      await tester.pumpAndSettle();

      expect(find.text('+20.0 /game'), findsNWidgets(2)); // legend, map
      expect(find.text('+80 RP'), findsOneWidget); // the session alone
    });

    testWidgets('is not offered when there is no best to name', (tester) async {
      // Two games: too few on any legend or map to name a best.
      await pump(tester, wins.take(2).toList());

      expect(find.text('Best legend'), findsNothing);
      expect(find.text('Rank by:'), findsNothing);
    });
  });

  testWidgets('shows the figures behind it, once each', (tester) async {
    // By RP per game, so the best legend's and map's figures aren't RP totals.
    await pump(tester, wins, saved: {'best_metric': 'rpPerGame'});

    // Four games of two kills and 400 damage, +20 RP each, all one session.
    expect(find.text('4'), findsOneWidget);
    // Peak RP, which is also where the climb finishes.
    expect(find.text('1,080'), findsNWidgets(2));
    expect(find.text('8'), findsOneWidget); // kills
    expect(find.text('1,600'), findsOneWidget); // damage
    expect(find.text('+80 RP'), findsOneWidget); // best session
    expect(find.text('Axle'), findsOneWidget); // best legend
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('4 wins · 0 losses'), findsOneWidget);
    expect(find.text('+20.0'), findsOneWidget);
  });

  testWidgets('leaves out the best legend and map nobody earned', (
    tester,
  ) async {
    await pump(tester, [
      buildMatch(start: t0, rp: 20, legend: 'Axle', map: 'olympus_rotation'),
      buildMatch(
        start: t0 + 1500,
        rp: 20,
        legend: 'Wraith',
        map: 'worlds_edge_rotation',
      ),
      buildMatch(
        start: t0 + 3000,
        rp: 20,
        legend: 'Octane',
        map: 'kings_canyon_rotation',
      ),
    ]);

    expect(find.text('Best legend'), findsNothing);
    expect(find.text('Best map'), findsNothing);
    // The others are still there.
    expect(find.text('Games'), findsOneWidget);
    expect(find.text('RP per game'), findsOneWidget);
  });

  testWidgets('a split with no kills reported reads them as none', (
    tester,
  ) async {
    await pump(tester, [
      for (var i = 0; i < 3; i++)
        buildMatch(start: t0 + i * 1500, rp: 20, cumulativeRp: 1020 + i * 20),
    ]);

    final tile = find.ancestor(
      of: find.text('Kills'),
      matching: find.byType(Container),
    );
    expect(
      find.descendant(of: tile.first, matching: find.text('—')),
      findsOneWidget,
    );
  });

  testWidgets('has no highlights rows, which the Overview already shows', (
    tester,
  ) async {
    await pump(tester, wins);

    expect(find.text('Highlights'), findsNothing);
    // The best legend and map are plain figures here, not tappable rows.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  group('sharing', () {
    testWidgets('keeps the card off the page, behind a button', (tester) async {
      await pump(tester, wins);

      expect(find.byType(RecapShareCard), findsNothing);
      expect(find.text('Share recap'), findsOneWidget);
    });

    testWidgets('the button opens the card, and its choice of tiles', (
      tester,
    ) async {
      await pump(tester, wins);

      await tester.tap(find.text('Share recap'));
      await tester.pumpAndSettle();

      expect(find.byType(RankedRecapShareScreen), findsOneWidget);
      expect(find.byType(RecapShareCard), findsOneWidget);
      expect(find.text('S30 Split 2 recap'), findsOneWidget);
    });

    testWidgets('reads Save where the platform cannot share a file', (
      tester,
    ) async {
      debugCanShareFiles = false;
      await pump(tester, wins);

      expect(find.text('Share recap'), findsNothing);
      expect(find.text('Save recap'), findsOneWidget);
    });
  });

  testWidgets('shows Apex Predator in the header', (tester) async {
    await pump(tester, wins, isPredator: true);

    expect(
      tester.widget<RankBadge>(find.byType(RankBadge)).assetPath,
      'assets/ranks/apex_predator.webp',
    );
  });

  testWidgets('a loss-making split is told in red, not green', (tester) async {
    await pump(tester, [
      for (var i = 0; i < 3; i++)
        buildMatch(start: t0 + i * 1500, rp: -20, cumulativeRp: 980 - i * 20),
    ]);

    final net = tester.widget<Text>(find.text('-60 RP this split'));
    expect(net.style?.color, AppTheme.red);
    final perGame = tester.widget<Text>(find.text('-20.0'));
    expect(perGame.style?.color, AppTheme.red);
  });
}
