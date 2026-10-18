import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_recap_share_screen.dart';
import 'package:apexlytics/utils/ranked/split_recap.dart';
import 'package:apexlytics/utils/share_image.dart';
import 'package:apexlytics/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

void main() {
  setUp(() => debugCanShareFiles = true);
  tearDown(() => debugCanShareFiles = null);

  final t0 = 1782090000;

  // Four wins on one legend and map: a best legend, map, session and streak.
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
  // Three losses, each on another legend and map: no best of either, no streak.
  final scattered = [
    buildMatch(start: t0, rp: -20, legend: 'Axle', map: 'olympus_rotation'),
    buildMatch(
      start: t0 + 1500,
      rp: -20,
      legend: 'Wraith',
      map: 'worlds_edge_rotation',
    ),
    buildMatch(
      start: t0 + 3000,
      rp: -20,
      legend: 'Octane',
      map: 'kings_canyon_rotation',
    ),
  ];

  late SharedPreferences prefs;

  Future<void> pump(
    WidgetTester tester, {
    List<RankedMatch>? matches,
    Map<String, Object> saved = const {},
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(saved);
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: RankedRecapShareScreen(
            recap: splitRecap(matches ?? wins),
            scope: 'S30 Split 2',
            playerName: 'Reptar',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A tile on the open card, by its label in capitals.
  Finder tile(String label) =>
      find.descendant(of: find.byType(ShareTile), matching: find.text(label));

  /// The chip that switches a tile on or off.
  Finder chip(String label) => find.widgetWithText(FilterChip, label);

  testWidgets('shows the recap card with the default tiles', (tester) async {
    await pump(tester);

    expect(find.text('Recap card'), findsOneWidget);
    expect(find.text('S30 Split 2 recap'), findsOneWidget);
    expect(find.byType(ShareTile), findsNWidgets(8));
    // Asked for, not shown to begin with.
    expect(tile('WIN RATE'), findsNothing);
    expect(tile('RP PER GAME'), findsNothing);
  });

  testWidgets('lays the tiles out two to a row, in order', (tester) async {
    await pump(tester);

    final rows = [
      ['GAMES', 'PEAK RP'],
      ['KILLS', 'DAMAGE'],
      ['BEST SESSION', 'TIME PLAYED'],
      ['BEST LEGEND', 'BEST MAP'],
    ];
    double? previousTop;
    for (final row in rows) {
      final left = tester.getTopLeft(tile(row[0]));
      final right = tester.getTopLeft(tile(row[1]));
      expect(left.dy, right.dy, reason: '$row share a row');
      expect(left.dx, lessThan(right.dx), reason: '$row in order');
      if (previousTop != null) expect(left.dy, greaterThan(previousTop));
      previousTop = left.dy;
    }
  });

  testWidgets('starts the tiles at the same place however many there are', (
    tester,
  ) async {
    await pump(tester);
    final eight = tester.getTopLeft(tile('GAMES')).dy;

    await tester.tap(chip('Win rate'));
    await tester.pump();
    await tester.tap(chip('RP per game'));
    await tester.pump();
    expect(find.byType(ShareTile), findsNWidgets(10));
    expect(tester.getTopLeft(tile('GAMES')).dy, eight);

    await tester.tap(chip('Kills'));
    await tester.pump();
    await tester.tap(chip('Damage'));
    await tester.pump();
    expect(tester.getTopLeft(tile('GAMES')).dy, eight);
  });

  testWidgets('has no comparison with the last split', (tester) async {
    await pump(tester);

    expect(chip('Vs last split'), findsNothing);
    expect(tile('VS LAST SPLIT'), findsNothing);
  });

  testWidgets('offers a chip for each tile, lit only when on the card', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Show on the card'), findsOneWidget);
    expect(find.text('Keep at least two.'), findsOneWidget);
    const on = [
      'Games',
      'Peak RP',
      'Kills',
      'Damage',
      'Best session',
      'Time played',
      'Best legend',
      'Best map',
    ];
    for (final label in on) {
      expect(chip(label), findsOneWidget, reason: label);
      expect(tester.widget<FilterChip>(chip(label)).selected, isTrue);
    }
    for (final label in ['Win rate', 'RP per game']) {
      expect(chip(label), findsOneWidget, reason: label);
      expect(tester.widget<FilterChip>(chip(label)).selected, isFalse);
    }
    // There is no win streak tile.
    expect(chip('Win streak'), findsNothing);
  });

  group('choosing the tiles', () {
    testWidgets('turning one off takes it off the card, and keeps that', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(chip('Kills'));
      await tester.pump();

      expect(tile('KILLS'), findsNothing);
      expect(find.byType(ShareTile), findsNWidgets(7));
      expect(tester.widget<FilterChip>(chip('Kills')).selected, isFalse);
      expect(
        prefs.getStringList(PrefsKeys.recapTiles),
        isNot(contains('kills')),
      );
    });

    testWidgets('turning it back on puts it back', (tester) async {
      await pump(tester);

      await tester.tap(chip('Kills'));
      await tester.pump();
      await tester.tap(chip('Kills'));
      await tester.pump();

      expect(tile('KILLS'), findsOneWidget);
      expect(find.byType(ShareTile), findsNWidgets(8));
    });

    testWidgets('turns on the win rate and RP per game when asked', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(chip('Win rate'));
      await tester.pump();
      await tester.tap(chip('RP per game'));
      await tester.pump();

      expect(find.byType(ShareTile), findsNWidgets(10));
      // Four wins of +20 RP each.
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('+20.0'), findsOneWidget);
      // They come last, after the best map.
      final map = tester.getTopLeft(tile('BEST MAP')).dy;
      expect(tester.getTopLeft(tile('WIN RATE')).dy, greaterThan(map));
      expect(tester.getTopLeft(tile('RP PER GAME')).dy, greaterThan(map));
    });

    testWidgets('keeps them on once turned on', (tester) async {
      await pump(
        tester,
        saved: {
          PrefsKeys.recapTiles: ['games', 'winRate', 'rpPerGame'],
        },
      );

      expect(find.byType(ShareTile), findsNWidgets(3));
      expect(tile('WIN RATE'), findsOneWidget);
      expect(tile('RP PER GAME'), findsOneWidget);
    });

    testWidgets('comes back as it was left', (tester) async {
      await pump(
        tester,
        saved: {
          PrefsKeys.recapTiles: ['games', 'peakRp', 'damage'],
        },
      );

      expect(find.byType(ShareTile), findsNWidgets(3));
      expect(tile('DAMAGE'), findsOneWidget);
      expect(tile('KILLS'), findsNothing);
    });

    testWidgets('keeps at least two, and leaves the last two switched on', (
      tester,
    ) async {
      await pump(
        tester,
        saved: {
          PrefsKeys.recapTiles: ['games', 'peakRp'],
        },
      );

      expect(tester.widget<FilterChip>(chip('Games')).onSelected, isNull);
      await tester.tap(chip('Games'), warnIfMissed: false);
      await tester.pump();

      expect(find.byType(ShareTile), findsNWidgets(2));
      expect(tile('GAMES'), findsOneWidget);
    });

    testWidgets('can always turn another one on from two', (tester) async {
      await pump(
        tester,
        saved: {
          PrefsKeys.recapTiles: ['games', 'peakRp'],
        },
      );

      await tester.tap(chip('Kills'));
      await tester.pump();

      expect(find.byType(ShareTile), findsNWidgets(3));
      // And now the others can come off again.
      expect(tester.widget<FilterChip>(chip('Games')).onSelected, isNotNull);
    });

    testWidgets('does not offer what nothing earned', (tester) async {
      await pump(tester, matches: scattered);

      // No best legend or map among three games each on its own.
      expect(chip('Best legend'), findsNothing);
      expect(chip('Best map'), findsNothing);
      expect(tile('BEST LEGEND'), findsNothing);
      // The rest are still there, win rate and RP per game among them.
      expect(chip('Games'), findsOneWidget);
      expect(chip('Win rate'), findsOneWidget);
      expect(chip('RP per game'), findsOneWidget);
      expect(chip('Best session'), findsOneWidget);
    });

    testWidgets('a choice for a tile this period cannot show is not honoured', (
      tester,
    ) async {
      await pump(
        tester,
        matches: scattered,
        saved: {
          PrefsKeys.recapTiles: ['games', 'peakRp', 'bestLegend'],
        },
      );

      expect(tile('BEST LEGEND'), findsNothing);
      expect(find.byType(ShareTile), findsNWidgets(2));
    });
  });

  group('the figures on the tiles', () {
    testWidgets('are totals of kills and damage, and the best session', (
      tester,
    ) async {
      await pump(tester);

      // Four games of two kills and 400 damage, and one session of +80.
      expect(
        find.descendant(
          of: find.widgetWithText(ShareTile, 'KILLS'),
          matching: find.text('8'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(ShareTile, 'DAMAGE'),
          matching: find.text('1,600'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(ShareTile, 'BEST SESSION'),
          matching: find.text('+80 RP'),
        ),
        findsOneWidget,
      );
    });
  });

  group('the card to share', () {
    testWidgets('has the name switch and the Share button', (tester) async {
      await pump(tester);

      expect(find.text('Reptar'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.text('Reptar'), findsNothing);
    });

    testWidgets('saves the image where a file cannot be shared', (
      tester,
    ) async {
      debugCanShareFiles = false;
      await pump(tester);

      expect(find.text('Save image'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('puts the choice of tiles between the card and the switch', (
      tester,
    ) async {
      await pump(tester);

      final card = tester.getBottomLeft(find.text('S30 Split 2 recap')).dy;
      final picker = tester.getTopLeft(find.text('Show on the card')).dy;
      final toggle = tester.getTopLeft(find.text('Show my name')).dy;
      expect(card, lessThan(picker));
      expect(picker, lessThan(toggle));
    });
  });
}
