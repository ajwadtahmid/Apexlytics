import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/screens/search/player_compare_screen.dart';
import 'package:apexlytics/widgets/legend_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  LegendTracker t(String name, int value) =>
      buildTracker(key: name.toLowerCase(), displayName: name, value: value);

  LegendStat legend(
    String name, {
    int games = 50,
    int kills = 100,
    int damage = 20000,
    int wins = 5,
    DateTime? updated,
  }) => LegendStat(
    name: name,
    trackers: [
      t('BR Games Played', games),
      t('BR Kills', kills),
      t('BR Damage', damage),
      t('BR Wins', wins),
    ],
    lastUpdated: updated,
  );

  final me = buildStats(
    name: 'Me',
    uid: 'a',
    rankScore: 7600, // Gold II, 80% through it, 150 RP from Gold I
    legendStats: [
      legend('Wraith', games: 100, kills: 200, damage: 40000),
      legend('Octane', games: 5),
    ],
  );
  final them = buildStats(
    name: 'Rival',
    uid: 'b',
    rankScore: 5600, // Gold IV
    legendStats: [
      legend('Wraith', games: 30, kills: 90, damage: 12000),
      legend('Octane', games: 200),
      legend('Pathfinder', games: 10),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    PlayerStats? mine,
    PlayerStats? theirs,
    Size size = const Size(400, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: PlayerCompareScreen(me: mine ?? me, them: theirs ?? them),
        ),
      ),
    );
  }

  group('the ranked view', () {
    testWidgets('names both players, and says who leads on how many stats', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Me'), findsOneWidget);
      expect(find.text('Rival'), findsWidgets); // the card and the key
      // Rank, RP and RP needed (150 against 650) all favour you.
      expect(find.text('You lead on 3 of 3 stats'), findsOneWidget);
    });

    testWidgets('shows the gap on the rows, counted in divisions for rank', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Rank'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget); // two divisions ahead
      expect(find.text('+2,000'), findsOneWidget); // RP
    });

    testWidgets('says so when the other player leads', (tester) async {
      await pump(tester, mine: them, theirs: me);

      expect(find.text('Me leads on 3 of 3 stats'), findsOneWidget);
    });
  });

  group('the legend view', () {
    Future<void> openLegends(WidgetTester tester, {Size? size}) async {
      await pump(tester, size: size ?? const Size(400, 900));
      await tester.tap(find.text('Legend'));
      await tester.pump(const Duration(milliseconds: 250));
    }

    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
    }

    Finder inSheet(String text) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(text),
    );

    testWidgets('starts on the legend you share the most', (tester) async {
      await openLegends(tester);

      // Wraith: 30 on the thinner side, against 5 for Octane.
      expect(find.text('Wraith'), findsOneWidget);
      expect(find.text('Games: you 100 · them 30'), findsOneWidget);
    });

    testWidgets('says nothing about games when neither of you tracks them', (
      tester,
    ) async {
      LegendStat bare() => LegendStat(
        name: 'Ash',
        trackers: [t('BR Kills', 10), t('BR Damage', 3000)],
      );
      await pump(
        tester,
        mine: buildStats(name: 'Me', uid: 'a', legendStats: [bare()]),
        theirs: buildStats(name: 'Rival', uid: 'b', legendStats: [bare()]),
      );
      await tester.tap(find.text('Legend'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.textContaining('Games'), findsNothing);
    });

    testWidgets('shows the trackers first and the calculated figures after, '
        'both from the start', (tester) async {
      await openLegends(tester);

      expect(find.text('Trackers'), findsOneWidget);
      expect(find.text('Calculated'), findsOneWidget);
      expect(find.text('BR Kills'), findsOneWidget); // the tracker's real name
      expect(find.text('Damage per Kill'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Trackers')).dy,
        lessThan(tester.getTopLeft(find.text('Calculated')).dy),
      );
      expect(
        tester.getTopLeft(find.text('BR Kills')).dy,
        lessThan(tester.getTopLeft(find.text('Damage per Kill')).dy),
      );
      expect(find.text('Show'), findsNothing);
      expect(find.text('Hide'), findsNothing);
    });

    testWidgets('games played is shown with no verdict, as context', (
      tester,
    ) async {
      await openLegends(tester);

      expect(find.text('BR Games Played'), findsOneWidget);
    });

    testWidgets('opens a grid with the legends you both play first', (
      tester,
    ) async {
      await openLegends(tester);
      await openPicker(tester);

      expect(find.text('Choose a legend'), findsOneWidget);
      expect(find.text('You both play'), findsOneWidget);
      expect(find.text('Only one of you'), findsOneWidget);

      double top(String name) => tester.getTopLeft(inSheet(name)).dy;
      double left(String name) => tester.getTopLeft(inSheet(name)).dx;
      // Wraith then Octane across the first row, Pathfinder in the next group.
      expect(top('Wraith'), top('Octane'));
      expect(left('Wraith'), lessThan(left('Octane')));
      expect(top('Pathfinder'), greaterThan(top('Octane')));
      // No games line under a tile: few players equip that tracker.
      expect(inSheet('100 · 30'), findsNothing);
    });

    testWidgets('no tile shows a games line, tracked or not', (tester) async {
      await openLegends(tester);
      await openPicker(tester);

      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('·'),
        ),
        findsNothing,
      );
      expect(inSheet('—'), findsNothing);
    });

    testWidgets('the career entry shows the app logo, not a blank', (
      tester,
    ) async {
      await pump(
        tester,
        mine: buildStats(
          name: 'Me',
          uid: 'a',
          legendStats: [legend('Global', games: 500)],
        ),
        theirs: buildStats(
          name: 'Rival',
          uid: 'b',
          legendStats: [legend('Global', games: 300)],
        ),
      );
      await tester.tap(find.text('Legend'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Career'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is ResizeImage &&
              (w.image as ResizeImage).imageProvider is AssetImage &&
              ((w.image as ResizeImage).imageProvider as AssetImage)
                      .assetName ==
                  kCareerIconAsset,
        ),
        findsOneWidget,
      );
    });

    testWidgets('picking a legend in the grid changes the comparison', (
      tester,
    ) async {
      await openLegends(tester);
      await openPicker(tester);

      await tester.tap(inSheet('Pathfinder')); // only they have it
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Games: you — · them 10'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('warns about a small sample', (tester) async {
      await pump(
        tester,
        mine: buildStats(
          name: 'Me',
          uid: 'a',
          legendStats: [legend('Wraith', games: 2)],
        ),
      );
      await tester.tap(find.text('Legend'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.textContaining('Few games on this legend'), findsOneWidget);
    });

    testWidgets('says when there is nothing to compare', (tester) async {
      await pump(
        tester,
        mine: buildStats(name: 'Me', uid: 'a'),
        theirs: buildStats(name: 'Rival', uid: 'b'),
      );
      await tester.tap(find.text('Legend'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.text('Neither of you has legend stats to compare yet.'),
        findsOneWidget,
      );
    });

    testWidgets('notes when a figure is more than a day old', (tester) async {
      await pump(
        tester,
        mine: buildStats(
          name: 'Me',
          uid: 'a',
          legendStats: [
            legend(
              'Wraith',
              updated: DateTime.now().subtract(const Duration(days: 3)),
            ),
          ],
        ),
      );
      await tester.tap(find.text('Legend'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.textContaining('Updated: you'), findsOneWidget);
    });
  });

  group('on a narrow screen with large text', () {
    for (final (width, scale) in [(320.0, 1.3), (320.0, 2.0), (360.0, 1.5)]) {
      testWidgets('the ranked view fits at ${width.toInt()} dp, ×$scale', (
        tester,
      ) async {
        await pump(
          tester,
          size: Size(width, 700),
          textScale: scale,
          theirs: buildStats(
            name: 'A Very Long Player Name That Keeps Going',
            uid: 'b',
            rankScore: 16500,
            rank: 'Master',
          ),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('the legend view and its picker fit at ${width.toInt()} dp, '
          '×$scale', (tester) async {
        await pump(tester, size: Size(width, 700), textScale: scale);
        await tester.tap(find.text('Legend'));
        await tester.pump(const Duration(milliseconds: 250));
        // The picker first, while the selector card is built.
        await tester.ensureVisible(find.text('Change'));
        await tester.pump();
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        expect(find.text('Choose a legend'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.text('Wraith'),
              )
              .first,
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Calculated'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
