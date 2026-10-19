import 'dart:io';
import 'dart:typed_data';

import 'package:apexlytics/screens/ranked/ranked_recap_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_share_screens.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_share_cards.dart';
import 'package:apexlytics/utils/ranked/ranked_period.dart';
import 'package:apexlytics/utils/ranked/recap_tiles.dart';
import 'package:apexlytics/utils/ranked/split_recap.dart';
import 'package:apexlytics/utils/share_image.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/rank_badge.dart';
import 'package:apexlytics/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import '../helpers.dart';

void main() {
  final t0 = 1782090000;
  final matches = [
    for (var i = 0; i < 4; i++)
      buildMatch(
        start: t0 + i * 1500,
        rp: 20,
        cumulativeRp: 1020 + i * 20,
        kills: 2,
        damage: 400,
      ),
  ];

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pump();
  }

  group('the recap card', () {
    testWidgets('shows the numbers, and the name only when given', (
      tester,
    ) async {
      final recap = splitRecap(matches);
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(
            recap: recap,
            scope: 'S30 Split 2',
            playerName: 'Reptar',
          ),
        ),
      );

      expect(find.text('S30 Split 2 recap'), findsOneWidget);
      expect(find.text('Reptar'), findsOneWidget);
      expect(find.text('1,080 RP'), findsOneWidget);
      expect(find.text('+80 RP this split'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // games
      expect(find.text('Axle'), findsOneWidget); // best legend

      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: recap, scope: 'S30 Split 2'),
        ),
      );
      expect(find.text('Reptar'), findsNothing);
    });

    testWidgets('says RP and the split under the finishing RP', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: splitRecap(matches), scope: 'S30'),
        ),
      );

      expect(find.text('+80 RP this split'), findsOneWidget);
      expect(find.textContaining('this period'), findsNothing);
    });

    testWidgets('says week when a single week is on screen', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(
            recap: splitRecap(matches),
            scope: 'S30 Split 2',
            periodPhrase: 'in Week 4',
          ),
        ),
      );

      expect(find.text('+80 RP in Week 4'), findsOneWidget);
    });

    testWidgets('has eight tiles to begin with, two to a row', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: splitRecap(matches), scope: 'S30'),
        ),
      );

      expect(find.byType(ShareTile), findsNWidgets(8));
      final rows = [
        ['GAMES', 'PEAK RP'],
        ['KILLS', 'DAMAGE'],
        ['BEST SESSION', 'TIME PLAYED'],
        ['BEST LEGEND', 'BEST MAP'],
      ];
      double? previousTop;
      for (final row in rows) {
        final left = tester.getTopLeft(find.text(row[0]));
        final right = tester.getTopLeft(find.text(row[1]));
        expect(left.dy, right.dy, reason: '$row share a row');
        expect(left.dx, lessThan(right.dx), reason: '$row in order');
        if (previousTop != null) expect(left.dy, greaterThan(previousTop));
        previousTop = left.dy;
      }
    });

    testWidgets('leaves the win rate and RP per game for when they are asked '
        'for, and has no win streak', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: splitRecap(matches), scope: 'S30'),
        ),
      );

      expect(find.text('WIN RATE'), findsNothing);
      expect(find.text('RP PER GAME'), findsNothing);
      expect(find.text('WIN STREAK'), findsNothing);
    });

    testWidgets('shows kills and damage as totals', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: splitRecap(matches), scope: 'S30'),
        ),
      );

      // Four games of two kills and 400 damage.
      expect(find.text('8'), findsOneWidget);
      expect(find.text('1,600'), findsOneWidget);
    });

    testWidgets('shows the best session by the RP it gained', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: splitRecap(matches), scope: 'S30'),
        ),
      );

      // The four wins are one session of +80.
      expect(
        find.descendant(
          of: find.widgetWithText(ShareTile, 'BEST SESSION'),
          matching: find.text('+80 RP'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('reads kills and damage as none when no game reported them', (
      tester,
    ) async {
      final bare = [
        for (var i = 0; i < 3; i++)
          buildMatch(start: t0 + i * 1500, rp: 20, cumulativeRp: 1020 + i * 20),
      ];
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: splitRecap(bare), scope: 'S30'),
        ),
      );

      for (final label in ['KILLS', 'DAMAGE']) {
        expect(
          find.descendant(
            of: find.widgetWithText(ShareTile, label),
            matching: find.text('—'),
          ),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets('shows the win rate and RP per game when they are given', (
      tester,
    ) async {
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(
            recap: splitRecap(matches),
            scope: 'S30',
            tiles: const [RecapTile.winRate, RecapTile.rpPerGame],
          ),
        ),
      );

      // Four wins of four games, +20 RP each.
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('+20.0'), findsOneWidget);
    });

    testWidgets('a split of only losses has a win rate of 0% and a negative '
        'RP per game', (tester) async {
      final losses = [
        for (var i = 0; i < 3; i++)
          buildMatch(start: t0 + i * 1500, rp: -20, cumulativeRp: 980 - i * 20),
      ];
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(
            recap: splitRecap(losses),
            scope: 'S30',
            tiles: const [RecapTile.winRate, RecapTile.rpPerGame],
          ),
        ),
      );

      expect(find.text('0%'), findsOneWidget);
      expect(find.text('-20.0'), findsOneWidget);
      expect(find.byType(ShareTile), findsNWidgets(2));
    });

    testWidgets('draws only the tiles it is given, in that order', (
      tester,
    ) async {
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(
            recap: splitRecap(matches),
            scope: 'S30',
            tiles: const [RecapTile.peakRp, RecapTile.games],
          ),
        ),
      );

      expect(find.byType(ShareTile), findsNWidgets(2));
      final peak = tester.getTopLeft(find.text('PEAK RP'));
      final games = tester.getTopLeft(find.text('GAMES'));
      // Side by side on one row, the first given on the left.
      expect(peak.dy, games.dy);
      expect(peak.dx, lessThan(games.dx));
    });

    testWidgets('fits all ten tiles', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(
            recap: splitRecap(matches),
            scope: 'S30 Split 2',
            playerName: 'A Rather Long Player Name',
            tiles: RecapTile.values,
          ),
        ),
      );

      expect(find.byType(ShareTile), findsNWidgets(10));
      expect(tester.takeException(), isNull);
    });
  });

  group('the recap badge', () {
    String? badge(WidgetTester tester) =>
        tester.widget<RankBadge>(find.byType(RankBadge)).assetPath;

    testWidgets('shows Apex Predator for a predator, and the match badge '
        'otherwise', (tester) async {
      // Match history only ever says Master, even for a predator.
      final recap = splitRecap([
        for (var i = 0; i < 4; i++)
          buildMatch(start: t0 + i * 1500, cumulativeRp: 15000 + i * 20),
      ]);
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: recap, scope: 'x', isPredator: true),
        ),
      );
      expect(badge(tester), 'assets/ranks/apex_predator.webp');

      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: recap, scope: 'x'),
        ),
      );
      // The match's own image is diamond4: that division's badge.
      expect(badge(tester), 'assets/ranks/diamond_4.webp');
    });
  });

  group('the other cards', () {
    testWidgets('the name leads in white and large, the record under it small '
        'and muted', (tester) async {
      await pump(
        tester,
        const Scaffold(
          body: RecordShareCard(
            record: 'Most Kills',
            value: '14',
            playerName: 'Reptar',
          ),
        ),
      );

      final name = tester.widget<Text>(find.text('Reptar'));
      final record = tester.widget<Text>(find.text('Most Kills'));
      expect(name.style!.color, Colors.white);
      expect(name.style!.fontSize, greaterThan(record.style!.fontSize!));
      expect(record.style!.color, AppTheme.muted);
      expect(
        tester.getTopLeft(find.text('Reptar')).dy,
        lessThan(tester.getTopLeft(find.text('Most Kills')).dy),
      );
    });

    testWidgets('with the name hidden the record leads instead', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(
          body: RecordShareCard(record: 'Most Kills', value: '14'),
        ),
      );

      final record = tester.widget<Text>(find.text('Most Kills'));
      expect(record.style!.color, Colors.white);
      expect(record.style!.fontSize, greaterThan(18));
    });

    testWidgets('carries the Apexlytics mark once, at the bottom right', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(
          body: RecordShareCard(
            record: 'Most Kills',
            value: '14',
            playerName: 'Reptar',
          ),
        ),
      );

      expect(find.text('APEXLYTICS'), findsOneWidget);
      expect(find.text('Made with Apexlytics'), findsNothing);
      final brand = tester.getBottomRight(find.text('APEXLYTICS'));
      final card = tester.getRect(find.byType(ShareCardFrame));
      // Under the content, and at the card's right edge.
      expect(brand.dy, greaterThan(tester.getBottomLeft(find.text('14')).dy));
      expect(card.right - brand.dx, lessThan(30));
    });

    testWidgets('a record card shows its figure and the numbers around it', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(
          body: RecordShareCard(
            record: 'Most Kills',
            value: '14',
            unit: 'kills',
            detail: 'Mar 4, 9:30 PM',
            playerName: 'Reptar',
            comparison: '4.5× your average',
            legend: 'Axle',
            stats: [
              (Icons.person_outline, 'Legend', 'Axle'),
              (Icons.map_outlined, 'Map', 'Olympus'),
            ],
          ),
        ),
      );

      expect(find.text('Most Kills'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('kills'), findsOneWidget);
      expect(find.text('4.5× your average'), findsOneWidget);
      expect(find.text('Reptar'), findsOneWidget);
      expect(find.text('Axle'), findsOneWidget);
      expect(find.text('LEGEND'), findsOneWidget);
    });

    testWidgets('is a 4:5 card, the recap taller, tiles in two columns', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(
          body: RecordShareCard(
            record: 'Most Kills',
            value: '14',
            unit: 'kills',
            stats: [
              (Icons.person_outline, 'Legend', 'Axle'),
              (Icons.map_outlined, 'Map', 'Olympus'),
              (Icons.bolt, 'RP', '+20'),
              (Icons.local_fire_department, 'Damage', '900'),
            ],
          ),
        ),
      );

      expect(tester.getSize(find.byType(ShareCardFrame)), const Size(360, 450));
      final legend = tester.getTopLeft(find.text('LEGEND'));
      final map = tester.getTopLeft(find.text('MAP'));
      final rp = tester.getTopLeft(find.text('RP'));
      expect(legend.dy, map.dy); // side by side
      expect(rp.dy, greaterThan(legend.dy)); // the next row
      expect(map.dx, greaterThan(legend.dx + 100));

      final recap = splitRecap(matches);
      await pump(
        tester,
        Scaffold(
          body: RecapShareCard(recap: recap, scope: 'x'),
        ),
      );
      expect(tester.getSize(find.byType(ShareCardFrame)), const Size(360, 560));
    });

    testWidgets('fades the legend portrait in behind the card', (tester) async {
      Finder portrait(String key) => find.byWidgetPredicate((w) {
        if (w is! Image) return false;
        final provider = w.image;
        final inner = provider is ResizeImage
            ? provider.imageProvider
            : provider;
        return inner is AssetImage &&
            inner.assetName == 'assets/legends/$key.webp';
      });

      await pump(
        tester,
        const Scaffold(
          body: RecordShareCard(
            record: 'Most Kills',
            value: '14',
            legend: 'Mad Maggie',
          ),
        ),
      );
      expect(portrait('mad_maggie'), findsOneWidget);

      await pump(
        tester,
        const Scaffold(
          body: RecordShareCard(record: 'Most Kills', value: '14'),
        ),
      );
      expect(portrait('mad_maggie'), findsNothing);
    });
  });

  group('the card of all records', () {
    const tiles = [
      (Icons.bolt, 'Best game', '+40 RP'),
      (Icons.sports_kabaddi, 'Most kills', '14'),
      (Icons.timeline, 'Best session', '+70 RP'),
      (Icons.schedule, 'Longest session', '2h 15m'),
    ];

    testWidgets('shows each record as a tile, under the scope', (tester) async {
      await pump(
        tester,
        const Center(
          child: RecordsShareCard(scope: 'S30 Split 2', tiles: tiles),
        ),
      );

      expect(find.text('S30 Split 2 records'), findsOneWidget);
      for (final label in [
        'BEST GAME',
        'MOST KILLS',
        'BEST SESSION',
        'LONGEST SESSION',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final value in ['+40 RP', '14', '+70 RP', '2h 15m']) {
        expect(find.text(value), findsOneWidget, reason: value);
      }
    });

    testWidgets('names the player only when given, and never a UID', (
      tester,
    ) async {
      await pump(
        tester,
        const Center(
          child: RecordsShareCard(
            scope: 'Ranked',
            tiles: tiles,
            playerName: 'Reptar',
          ),
        ),
      );
      expect(find.text('Reptar'), findsOneWidget);
      expect(find.text('Ranked records'), findsOneWidget);

      await pump(
        tester,
        const Center(
          child: RecordsShareCard(scope: 'Ranked', tiles: tiles),
        ),
      );
      expect(find.text('Reptar'), findsNothing);
      expect(find.textContaining('uid'), findsNothing);
    });

    testWidgets('fits its tiles on the card with eight of them', (
      tester,
    ) async {
      await pump(
        tester,
        const Center(
          child: RecordsShareCard(
            scope: 'S30 Split 2',
            playerName: 'A Rather Long Player Name',
            tiles: [
              (Icons.bolt, 'Best game', '+40 RP'),
              (Icons.sports_kabaddi, 'Most kills', '14'),
              (Icons.local_fire_department, 'Most damage', '2,840'),
              (Icons.timeline, 'Best session', '+70 RP'),
              (Icons.calendar_today_outlined, 'Best day', '+110 RP'),
              (Icons.schedule, 'Longest session', '2h 15m'),
              (Icons.trending_up, 'Comeback', '+45 RP'),
              (Icons.military_tech, 'Win streak', '8 games'),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('the streak card', () {
    // Five wins on three legends, Axle most.
    final streak = [
      for (var i = 0; i < 5; i++)
        buildMatch(
          start: t0 + i * 1500,
          rp: 20,
          legend: i < 3 ? 'Axle' : (i == 3 ? 'Wraith' : 'Octane'),
          kills: i + 1,
          damage: 100 * (i + 1),
        ),
    ];

    testWidgets('shows the length, a dot for every win and the RP earned', (
      tester,
    ) async {
      await pump(
        tester,
        Scaffold(
          body: StreakShareCard(matches: streak, playerName: 'Reptar'),
        ),
      );

      expect(find.text('Best Win Streak'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('games'), findsOneWidget);
      expect(find.text('+100 RP across the streak'), findsOneWidget);
      final dots = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(dots, findsNWidgets(5));
    });

    testWidgets('totals the streak and names the legend that earned most RP', (
      tester,
    ) async {
      await pump(tester, Scaffold(body: StreakShareCard(matches: streak)));

      expect(find.text('15'), findsOneWidget); // kills 1+2+3+4+5
      expect(find.text('1,500'), findsOneWidget); // damage
      expect(find.text('Axle'), findsOneWidget); // three wins, 60 RP
      expect(find.text('TOP LEGEND'), findsOneWidget);
      expect(find.textContaining('RP)'), findsNothing); // no RP on the tile
      expect(find.text('FIRST TO LAST WIN'), findsOneWidget);
    });

    testWidgets('the top legend is the one that earned most RP, not the one '
        'played most', (tester) async {
      final mixed = [
        buildMatch(start: t0, rp: 10, legend: 'Axle'),
        buildMatch(start: t0 + 1500, rp: 10, legend: 'Axle'),
        buildMatch(start: t0 + 3000, rp: 90, legend: 'Octane'),
      ];
      await pump(tester, Scaffold(body: StreakShareCard(matches: mixed)));

      expect(find.text('Octane'), findsOneWidget);
      expect(find.text('Axle'), findsNothing);
    });

    testWidgets('a streak on one legend says so', (tester) async {
      final one = [
        for (var i = 0; i < 3; i++)
          buildMatch(start: t0 + i * 1500, rp: 10, legend: 'Conduit'),
      ];
      await pump(tester, Scaffold(body: StreakShareCard(matches: one)));

      expect(find.text('Only Conduit'), findsOneWidget);
    });

    testWidgets('a very long streak shows the rest as a count', (tester) async {
      final long = [
        for (var i = 0; i < 45; i++) buildMatch(start: t0 + i * 1000, rp: 10),
      ];
      await pump(tester, Scaffold(body: StreakShareCard(matches: long)));

      expect(find.text('+15'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
    });
  });

  group('the share screen', () {
    setUp(() => debugCanShareFiles = true);
    tearDown(() => debugCanShareFiles = null);

    testWidgets('the name toggle hides the name, and Share captures the card', (
      tester,
    ) async {
      GlobalKey? captured;
      await pump(
        tester,
        ShareCardScreen(
          title: 'Most Kills',
          cardBuilder: (show) => RecordShareCard(
            record: 'Most Kills',
            value: '14',
            playerName: show ? 'Reptar' : null,
          ),
          onShare: (key) async {
            captured = key;
            return true;
          },
        ),
      );
      expect(find.text('Reptar'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(find.text('Reptar'), findsNothing);

      await tester.tap(find.text('Share'));
      await tester.pump();
      expect(captured, isNotNull);
    });

    testWidgets('a failed share says so instead of crashing', (tester) async {
      await pump(
        tester,
        ShareCardScreen(
          title: 'Most Kills',
          cardBuilder: (_) =>
              const RecordShareCard(record: 'Most Kills', value: '14'),
          onShare: (_) async => throw Exception('no share sheet'),
        ),
      );

      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pump();

      expect(find.text("Couldn't share the card."), findsOneWidget);
    });
  });

  group('the share screen where a file cannot be shared', () {
    setUp(() => debugCanShareFiles = false);
    tearDown(() => debugCanShareFiles = null);

    Widget screen({Future<String?> Function(GlobalKey key)? onSave}) =>
        ShareCardScreen(
          title: 'Most Kills',
          cardBuilder: (show) => RecordShareCard(
            record: 'Most Kills',
            value: '14',
            playerName: show ? 'Reptar' : null,
          ),
          onSave: onSave,
        );

    testWidgets('offers Save image, not Share', (tester) async {
      await pump(tester, screen());

      expect(find.text('Save image'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('saves the card and says where', (tester) async {
      GlobalKey? captured;
      await pump(
        tester,
        screen(
          onSave: (key) async {
            captured = key;
            return '/tmp/apexlytics_card.png';
          },
        ),
      );

      await tester.tap(find.text('Save image'));
      await tester.pump();
      await tester.pump();

      expect(captured, isNotNull);
      expect(find.text('Saved to /tmp/apexlytics_card.png'), findsOneWidget);
    });

    testWidgets('says nothing when the save dialog is cancelled', (
      tester,
    ) async {
      await pump(tester, screen(onSave: (_) async => null));

      await tester.tap(find.text('Save image'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed save says so instead of crashing', (tester) async {
      await pump(
        tester,
        screen(onSave: (_) async => throw Exception('disk full')),
      );

      await tester.tap(find.text('Save image'));
      await tester.pump();
      await tester.pump();

      expect(find.text("Couldn't save the card."), findsOneWidget);
    });

    testWidgets('keeps the name toggle', (tester) async {
      await pump(tester, screen());
      expect(find.text('Reptar'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.text('Reptar'), findsNothing);
    });
  });

  group('saving the image to a file', () {
    final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

    test('writes it where the user chose and says where', () async {
      final dir = await Directory.systemTemp.createTemp('apexlytics_save_');
      addTearDown(() => dir.delete(recursive: true));
      String? suggested;

      final saved = await saveImageFile(
        png,
        pickPath: (name) async {
          suggested = name;
          return '${dir.path}${Platform.pathSeparator}chosen.png';
        },
      );

      expect(suggested, 'apexlytics_card.png');
      expect(saved, '${dir.path}${Platform.pathSeparator}chosen.png');
      expect(await File(saved!).readAsBytes(), png);
    });

    test('writes nothing when the user cancels', () async {
      final saved = await saveImageFile(png, pickPath: (_) async => null);

      expect(saved, isNull);
    });
  });

  group('whether a file can be shared', () {
    tearDown(() => debugCanShareFiles = null);

    test('is no on Linux and yes elsewhere, unless a test says otherwise', () {
      debugCanShareFiles = null;
      expect(canShareFiles, !Platform.isLinux);

      debugCanShareFiles = true;
      expect(canShareFiles, isTrue);
      debugCanShareFiles = false;
      expect(canShareFiles, isFalse);
    });
  });

  group('the image', () {
    testWidgets('is rendered 1080 px wide from a 360 px card', (tester) async {
      final key = GlobalKey();
      await pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: const RecordShareCard(record: 'Most Kills', value: '14'),
            ),
          ),
        ),
      );

      final png = await tester.runAsync(() => captureBoundaryAsPng(key));

      // A PNG: its signature, then the width in the IHDR chunk.
      expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final width = ByteData.sublistView(png).getUint32(16);
      expect(width, 1080);
    });

    test(
      'is shared from a temporary file that is deleted afterwards',
      () async {
        final dir = await Directory.systemTemp.createTemp('share_test');
        addTearDown(() => dir.delete(recursive: true));
        String? sharedPath;
        var existedWhileSharing = false;

        final ok = await shareImageFile(
          Uint8List.fromList([1, 2, 3]),
          dir: dir,
          share: (params) async {
            sharedPath = params.files!.single.path;
            existedWhileSharing = File(sharedPath!).existsSync();
            return const ShareResult('', ShareResultStatus.success);
          },
        );

        expect(ok, isTrue);
        expect(existedWhileSharing, isTrue);
        expect(File(sharedPath!).existsSync(), isFalse);
      },
    );

    test('a dismissed share sheet is not a success', () async {
      final dir = await Directory.systemTemp.createTemp('share_test');
      addTearDown(() => dir.delete(recursive: true));

      final ok = await shareImageFile(
        Uint8List.fromList([1]),
        dir: dir,
        share: (_) async => const ShareResult('', ShareResultStatus.dismissed),
      );

      expect(ok, isFalse);
    });
  });

  group('the entries', () {
    testWidgets('Recap opens the card for the period', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: RankedRecapEntry(
            matches: matches,
            scope: 'S30 Split 2',
            playerName: 'Reptar',
          ),
        ),
      );
      await tester.tap(find.text('Recap'));
      await tester.pumpAndSettle();
      // The recap page; the card to share is a tap further on.
      expect(find.byType(RankedRecapScreen), findsOneWidget);
      expect(find.text('S30 Split 2'), findsOneWidget);
      expect(find.byType(RecapShareCard), findsNothing);
    });

    testWidgets('Recap passes the predator status on to the card', (
      tester,
    ) async {
      await pump(
        tester,
        Scaffold(
          body: RankedRecapEntry(
            matches: matches,
            scope: 'S30 Split 2',
            playerName: 'Reptar',
            isPredator: true,
          ),
        ),
      );
      await tester.tap(find.text('Recap'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<RankBadge>(find.byType(RankBadge)).assetPath,
        'assets/ranks/apex_predator.webp',
      );
    });

    testWidgets('Recap says week when it is opened for a single week', (
      tester,
    ) async {
      await pump(
        tester,
        Scaffold(
          body: RankedRecapEntry(
            matches: matches,
            scope: 'S30 Split 2',
            playerName: 'Reptar',
            periodPhrase: 'in Week 4',
          ),
        ),
      );
      await tester.tap(find.text('Recap'));
      await tester.pumpAndSettle();

      expect(find.text('+80 RP in Week 4'), findsOneWidget);
    });

    test('names the period by whether a week is picked', () {
      RankedView view(int week) => RankedView(
        splits: const [],
        effectiveSplitId: '',
        weeks: const [],
        weekIndex: week,
        filtered: const [],
        history: const [],
      );

      expect(recapPeriodPhrase(view(-1)), 'this split');
      expect(recapPeriodPhrase(view(0)), 'in Week 1');
      expect(recapPeriodPhrase(view(3)), 'in Week 4');
    });

    test('a title can leave the week out', () {
      RankedView view(int week) => RankedView(
        splits: const [],
        effectiveSplitId: '',
        weeks: const [],
        weekIndex: week,
        filtered: const [],
        history: const [],
      );

      expect(recapScopeLabel(view(3)), 'Ranked Week 4');
      expect(recapScopeLabel(view(3), week: false), 'Ranked');
      expect(recapScopeLabel(view(-1), week: false), 'Ranked');
    });

    testWidgets('Recap with no games says so instead of opening', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(
          body: RankedRecapEntry(matches: [], scope: 'x', playerName: 'R'),
        ),
      );
      await tester.tap(find.text('Recap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No ranked games to recap yet.'), findsOneWidget);
    });
  });
}
