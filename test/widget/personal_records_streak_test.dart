import 'package:apexlytics/screens/ranked/ranked_personal_records_screen.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/share_image.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  // The buttons read Share where the platform can share a file; tests run on
  // whatever host they are on, so pin it.
  setUp(() => debugCanShareFiles = true);
  tearDown(() => debugCanShareFiles = null);

  // Three wins in a row, ending the scope.
  final matches = [
    buildMatch(start: 1782090000 + 3 * 1000, rp: 10),
    buildMatch(start: 1782090000 + 2 * 1000, rp: 10),
    buildMatch(start: 1782090000 + 1 * 1000, rp: 10),
  ];

  Future<void> pump(WidgetTester tester, {required bool live}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [allTimeBestOverride()],
        child: MaterialApp(
          home: RankedPersonalRecordsScreen(
            stats: buildStats(name: 'Reptar'),
            matches: matches,
            sessions: sessionize(matches),
            live: live,
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the screen is Personal Records, with no separate share section '
      'and no comparison', (tester) async {
    await pump(tester, live: true);

    expect(find.text('Personal Records'), findsOneWidget);
    expect(find.text('Share my profile'), findsNothing);
    // Each record here has its own labelled button (best game, session,
    // longest session and streak), and there is no other share section.
    expect(find.text('Share'), findsNWidgets(4));
    expect(find.text('Comparison'), findsNothing);
    expect(find.text('Legends'), findsNothing);
  });

  group('the records and their share buttons', () {
    // A session of four games with kills and damage reported.
    final played = [
      for (var i = 0; i < 4; i++)
        buildMatch(
          start: 1782090000 + (3 - i) * 1000,
          rp: i == 1 ? 40 : 10,
          kills: i + 1,
          damage: (i + 1) * 300,
        ),
    ];

    /// A figure's tile on the open share card (its label, in capitals).
    Finder tile(String label) =>
        find.descendant(of: find.byType(ShareTile), matching: find.text(label));

    Future<void> pumpPlayed(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [allTimeBestOverride()],
          child: MaterialApp(
            home: RankedPersonalRecordsScreen(
              stats: buildStats(name: 'Reptar'),
              matches: played,
              sessions: sessionize(played),
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('each record has one', (tester) async {
      await pumpPlayed(tester);

      for (final record in [
        'Most RP Gained',
        'Most Kills',
        'Most Damage',
        'Best Session',
        'Best Win Streak',
      ]) {
        expect(find.byTooltip('Share $record'), findsOneWidget, reason: record);
      }
    });

    testWidgets(
      'the best session shows RP first, then games, kills and damage',
      (tester) async {
        await pumpPlayed(tester);

        // All four games are one session on one day, so the day isn't shown
        // again beside it.
        expect(find.text('+70 RP'), findsOneWidget);
        expect(find.text('4 games · 10 kills · 3,000 dmg'), findsOneWidget);
      },
    );

    testWidgets('a share button opens that record as a card', (tester) async {
      await pumpPlayed(tester);

      await tester.tap(find.byTooltip('Share Most Kills'));
      await tester.pumpAndSettle();

      expect(find.text('Most Kills'), findsWidgets);
      expect(find.text('4'), findsWidgets);
      expect(find.text('kills'), findsWidgets);
      // The name can be shown or hidden, and the UID is never in it.
      expect(find.text('Show my name'), findsOneWidget);
      expect(find.textContaining('uid123'), findsNothing);
    });

    testWidgets('a game record card leads with its figure and does not repeat '
        'it, and puts it next to the period average', (tester) async {
      await pumpPlayed(tester);

      await tester.tap(find.byTooltip('Share Most Kills'));
      await tester.pumpAndSettle();

      // The figure is orange, bold and big.
      final figure = tester.widget<Text>(find.text('4').last);
      expect(figure.style!.color, AppTheme.accent);
      expect(figure.style!.fontSize, greaterThanOrEqualTo(40));
      expect(figure.style!.fontWeight, FontWeight.bold);
      expect(find.text('kills'), findsOneWidget); // its unit
      // The tiles carry the other numbers, not kills again.
      expect(tile('KILLS'), findsNothing);
      expect(tile('RP'), findsOneWidget);
      expect(tile('DAMAGE'), findsOneWidget);
      // 4 kills against an average of 2.5.
      expect(find.text('1.6× your average'), findsOneWidget);
    });

    testWidgets('the RP and damage cards drop their own figure and show their '
        'own average', (tester) async {
      await pumpPlayed(tester);

      await tester.tap(find.byTooltip('Share Most RP Gained'));
      await tester.pumpAndSettle();
      expect(tile('RP'), findsNothing);
      expect(tile('KILLS'), findsOneWidget);
      expect(tile('DAMAGE'), findsOneWidget);
      // +40 against an average of +17.5 a game.
      expect(find.text('2.3× your average'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Share Most Damage'));
      await tester.pumpAndSettle();
      expect(tile('DAMAGE'), findsNothing);
      expect(tile('RP'), findsOneWidget);
      // 1,200 damage against an average of 750.
      expect(find.text('1.6× your average'), findsOneWidget);
    });

    testWidgets('the session and streak records open as cards too', (
      tester,
    ) async {
      await pumpPlayed(tester);

      await tester.tap(find.byTooltip('Share Best Session'));
      await tester.pumpAndSettle();
      expect(find.text('Best Session'), findsWidgets);
      expect(find.text('TIME PLAYED'), findsOneWidget);
      // When it ran, with the times: "Oct 9 (11:12 AM – 3:34 PM)".
      expect(
        find.textContaining(
          // Within a day: Oct 9 (11:12 AM – 3:34 PM); across midnight: ... to ...
          RegExp(r'[AP]M( – .* [AP]M\)| to \w{3} \d+ .* [AP]M)'),
        ),
        findsWidgets,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Share Best Win Streak'));
      await tester.pumpAndSettle();
      expect(find.text('games'), findsWidgets);
    });

    testWidgets('a record with no data has no share button', (tester) async {
      await pump(tester, live: true); // these games reported no kills or damage

      expect(find.byTooltip('Share Most RP Gained'), findsOneWidget);
      expect(find.byTooltip('Share Most Kills'), findsNothing);
      expect(find.byTooltip('Share Most Damage'), findsNothing);
    });
  });

  testWidgets('a live scope tells the player they are on the streak now', (
    tester,
  ) async {
    await pump(tester, live: true);

    expect(find.text('3 games'), findsOneWidget);
    expect(find.text('You\'re on it now!'), findsOneWidget);
    expect(find.textContaining('since '), findsOneWidget);
  });

  testWidgets('a past week or split never says the player is on it now', (
    tester,
  ) async {
    // An old scope's trailing run isn't the player's streak today.
    await pump(tester, live: false);

    expect(find.text('3 games'), findsOneWidget);
    expect(find.text('You\'re on it now!'), findsNothing);
    expect(find.text('Ended on its best streak'), findsOneWidget);
    expect(find.textContaining('Currently'), findsNothing);
    expect(find.textContaining('since '), findsNothing);
    expect(find.textContaining('from '), findsOneWidget);
  });
}
