import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_entity_history_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_personal_records_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_session_detail_screen.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/share_image.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/utils/formatting/format.dart' show formatDuration;
import 'package:apexlytics/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  setUp(() => debugCanShareFiles = true);
  tearDown(() => debugCanShareFiles = null);

  // A session of four wins, each with kills and damage reported.
  final played = [
    for (var i = 0; i < 4; i++)
      buildMatch(
        start: 1782090000 + (3 - i) * 1000,
        rp: i == 1 ? 40 : 10,
        kills: i + 1,
        damage: (i + 1) * 300,
      ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    Override? allTime,
    List<RankedMatch>? games,
  }) async {
    final list = games ?? played;
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [allTime ?? allTimeBestOverride(), await prefsOverride()],
        child: MaterialApp(
          home: RankedPersonalRecordsScreen(
            stats: buildStats(name: 'Reptar'),
            matches: list,
            sessions: sessionize(list),
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The detail sheet's own date line, "Friday, October 9, 2026 · 3:34 PM".
  final gameSheet = find.textContaining(RegExp(r'^\w+, \w+ \d+, \d{4} · '));

  group('tapping a record', () {
    testWidgets('a single-game record opens the game it was set in', (
      tester,
    ) async {
      await pump(tester);
      expect(gameSheet, findsNothing);

      await tester.tap(find.text('4 kills'));
      await tester.pumpAndSettle();

      expect(gameSheet, findsOneWidget);
    });

    testWidgets('every one of the three does', (tester) async {
      await pump(tester);

      for (final figure in ['+40', '4 kills', '1,200 damage']) {
        await tester.tap(find.text(figure));
        await tester.pumpAndSettle();
        expect(gameSheet, findsOneWidget, reason: figure);
        await tester.tapAt(const Offset(5, 5)); // the scrim closes the sheet
        await tester.pumpAndSettle();
        expect(gameSheet, findsNothing, reason: figure);
      }
    });

    testWidgets('the best session opens that session', (tester) async {
      await pump(tester);

      await tester.tap(find.text('+70 RP'));
      await tester.pumpAndSettle();

      expect(find.byType(RankedSessionDetailScreen), findsOneWidget);
    });

    testWidgets('the best streak lists its games', (tester) async {
      await pump(tester);

      await tester.tap(find.text('4 games'));
      await tester.pumpAndSettle();

      expect(find.byType(RankedEntityHistoryScreen), findsOneWidget);
      expect(find.text('4 games · +70 RP'), findsOneWidget);
    });

    testWidgets('the share button opens the card, not the game', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byTooltip('Share Most Kills'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareCardScreen), findsOneWidget);
      expect(gameSheet, findsNothing);
    });

    testWidgets('a record with nothing to show does nothing', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Games that reported no kills or damage.
      final bare = [buildMatch(rp: 10)];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [allTimeBestOverride(), await prefsOverride()],
          child: MaterialApp(
            home: RankedPersonalRecordsScreen(
              stats: buildStats(name: 'Reptar'),
              matches: bare,
              sessions: sessionize(bare),
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('No data yet').first);
      await tester.pumpAndSettle();

      expect(gameSheet, findsNothing);
    });
  });

  group('against the best over every split', () {
    PersonalBestGames best({int rp = 10, int kills = 1, int damage = 100}) => (
      bestRpGame: buildMatch(rp: rp),
      bestKillsGame: buildMatch(kills: kills),
      bestDamageGame: buildMatch(damage: damage),
    );

    testWidgets('a record that is the all-time best says so, in orange', (
      tester,
    ) async {
      // The split's records are the all-time ones.
      await pump(tester, allTime: allTimeBestOverride(best()));

      expect(find.text('All-time best'), findsNWidgets(3));
      final note = tester.widget<Text>(find.text('All-time best').first);
      expect(note.style?.color, AppTheme.accent);
    });

    testWidgets('a record that is not says what the best is, muted', (
      tester,
    ) async {
      await pump(
        tester,
        allTime: allTimeBestOverride(best(rp: 86, kills: 14, damage: 2840)),
      );

      expect(find.text('All-time best: +86 RP'), findsOneWidget);
      expect(find.text('All-time best: 14 kills'), findsOneWidget);
      expect(find.text('All-time best: 2,840 damage'), findsOneWidget);
      expect(find.text('All-time best'), findsNothing);
      final note = tester.widget<Text>(find.text('All-time best: +86 RP'));
      expect(note.style?.color, AppTheme.muted);
    });

    testWidgets('each record is compared on its own', (tester) async {
      await pump(
        tester,
        allTime: allTimeBestOverride(best(rp: 40, kills: 14, damage: 100)),
      );

      // Best RP ties, kills fall short, damage is beaten.
      expect(find.text('All-time best'), findsNWidgets(2));
      expect(find.text('All-time best: 14 kills'), findsOneWidget);
    });

    testWidgets('says nothing where there are no all-time games to compare', (
      tester,
    ) async {
      await pump(tester);

      expect(find.textContaining('All-time'), findsNothing);
    });

    testWidgets('says nothing if the all-time games cannot be read', (
      tester,
    ) async {
      await pump(
        tester,
        allTime: rankedAllTimeBestProvider.overrideWith(
          (ref, uid) async => throw Exception('no database'),
        ),
      );

      expect(find.textContaining('All-time'), findsNothing);
      // The records are still there.
      expect(find.text('4 kills'), findsOneWidget);
    });

    testWidgets('the session and the streak have no all-time note', (
      tester,
    ) async {
      await pump(tester, allTime: allTimeBestOverride(best()));

      // Three single-game records, nothing for the other two.
      expect(find.textContaining('All-time'), findsNWidgets(3));
    });
  });

  group('where the platform cannot share a file', () {
    testWidgets('the buttons say Save, and the preview saves the image', (
      tester,
    ) async {
      debugCanShareFiles = false;
      await pump(tester);

      expect(find.text('Share'), findsNothing);
      expect(find.text('Save'), findsNWidgets(6));

      await tester.tap(find.byTooltip('Save Most Kills'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareCardScreen), findsOneWidget);
      expect(find.text('Save image'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
    });
  });

  group('the day, session and comeback records', () {
    int at(int day, int hour, [int minute = 0]) =>
        DateTime(2026, 10, day, hour, minute).millisecondsSinceEpoch ~/ 1000;
    RankedMatch g(int start, int rp, {int length = 600}) =>
        buildMatch(start: start, rp: rp, length: length, kills: 1, damage: 100);

    final rich = [
      // Oct 1: down to -30, then back up to +15.
      for (var i = 0; i < 4; i++)
        g(at(1, 18) + i * 1200, [-20, -10, 25, 20][i]),
      // Oct 2: an early session of +70 and a late one of +40, so +110 in a day.
      g(at(2, 18), 40),
      g(at(2, 18) + 1200, 30),
      g(at(2, 22), 30),
      g(at(2, 22) + 1200, 10),
      // Oct 3: two hour-long games 15 minutes apart, 2h 15m in all.
      g(at(3, 18), 5, length: 3600),
      g(at(3, 19, 15), 5, length: 3600),
    ];
    final day = DateFormat('EEE, MMM d').format(DateTime(2026, 10, 2));

    testWidgets('the best day shows its RP and games, and lists them', (
      tester,
    ) async {
      await pump(tester, games: rich);

      expect(find.text('Best Day'), findsOneWidget);
      expect(find.text('+110 RP'), findsOneWidget);
      expect(find.text('$day · 4 games'), findsOneWidget);

      await tester.tap(find.text('+110 RP'));
      await tester.pumpAndSettle();

      expect(find.byType(RankedEntityHistoryScreen), findsOneWidget);
      expect(find.text('$day · 4 games · +110 RP'), findsOneWidget);
    });

    testWidgets('the longest session shows its time, and opens', (
      tester,
    ) async {
      await pump(tester, games: rich);
      final time = formatDuration(135 * 60);

      expect(find.text('Longest Session'), findsOneWidget);
      expect(find.text(time), findsOneWidget);
      expect(find.text('2 games · +10 RP'), findsOneWidget);

      await tester.tap(find.text(time));
      await tester.pumpAndSettle();

      expect(find.byType(RankedSessionDetailScreen), findsOneWidget);
    });

    testWidgets('the biggest comeback says how far down and where it ended', (
      tester,
    ) async {
      await pump(tester, games: rich);

      expect(find.text('Biggest Comeback'), findsOneWidget);
      expect(find.text('+45 RP'), findsOneWidget);
      expect(find.text('Down 30 RP, finished +15'), findsOneWidget);

      await tester.tap(find.text('+45 RP'));
      await tester.pumpAndSettle();

      expect(find.byType(RankedSessionDetailScreen), findsOneWidget);
    });

    testWidgets('each can be shared as a card of its own', (tester) async {
      await pump(tester, games: rich);

      for (final title in ['Best Day', 'Longest Session', 'Biggest Comeback']) {
        await tester.tap(find.byTooltip('Share $title'));
        await tester.pumpAndSettle();
        expect(find.byType(ShareCardScreen), findsOneWidget, reason: title);
        expect(find.text(title), findsWidgets, reason: title);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a period with no comeback has no comeback card', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Biggest Comeback'), findsNothing);
      expect(find.text('Longest Session'), findsOneWidget);
    });

    testWidgets('hides the best day when it is just the best session', (
      tester,
    ) async {
      // All four games are one session on one day.
      await pump(tester);

      expect(find.text('Best Day'), findsNothing);
      expect(find.text('Best Session'), findsOneWidget);
    });

    testWidgets('shows the best day when it holds more than the best session', (
      tester,
    ) async {
      // +110 over two sessions on Oct 2, against the best single session's +70.
      await pump(tester, games: rich);

      expect(find.text('Best Day'), findsOneWidget);
      expect(find.text('Best Session'), findsOneWidget);
    });
  });

  group('the card of all records', () {
    /// A tile's label on the open card, in capitals.
    Finder tile(String label) =>
        find.descendant(of: find.byType(ShareTile), matching: find.text(label));

    testWidgets('has a button at the top, and opens one card', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Share all my records'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareCardScreen), findsOneWidget);
      expect(find.text('My records'), findsOneWidget);
      expect(find.text('Ranked records'), findsOneWidget);
    });

    testWidgets('has a tile for each record the period has', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Share all my records'));
      await tester.pumpAndSettle();

      for (final label in [
        'BEST GAME',
        'MOST KILLS',
        'MOST DAMAGE',
        'BEST SESSION',
        'LONGEST SESSION',
        'WIN STREAK',
      ]) {
        expect(tile(label), findsOneWidget, reason: label);
      }
      // These games never dipped and came back, and the day is the session.
      expect(tile('COMEBACK'), findsNothing);
      expect(tile('BEST DAY'), findsNothing);
    });

    testWidgets('adds the comeback when there was one', (tester) async {
      await pump(
        tester,
        games: [
          for (var i = 0; i < 4; i++)
            buildMatch(
              start: 1782090000 + i * 1200,
              rp: [-20, -10, 25, 20][i],
              kills: 1,
              damage: 100,
            ),
        ],
      );

      await tester.tap(find.text('Share all my records'));
      await tester.pumpAndSettle();

      expect(tile('COMEBACK'), findsOneWidget);
    });

    testWidgets('can hide the name', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Share all my records'));
      await tester.pumpAndSettle();
      expect(find.text('Reptar'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.text('Reptar'), findsNothing);
    });

    testWidgets('reads Save where the platform cannot share a file', (
      tester,
    ) async {
      debugCanShareFiles = false;
      await pump(tester);

      expect(find.text('Share all my records'), findsNothing);
      expect(find.text('Save all my records'), findsOneWidget);
    });
  });
}
