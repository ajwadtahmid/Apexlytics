import 'dart:io' show File, Platform;
import 'dart:typed_data' show ByteData;

import 'package:apexlytics/screens/ranked/widgets/ranked_highlight_cards.dart';
import 'package:apexlytics/utils/ranked/best_metric.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/rp_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets('every legend card puts its RP pill at the same right edge, '
      'whatever the pill reads', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Different RP per game, so the pills have different widths.
    final legends = [
      for (final (name, rp) in [
        ('Axle', 5),
        ('Wraith', 144),
        ('Bangalore', 256),
        ('Octane', -30),
      ])
        (RankedAgg()..addAll([
              for (var i = 0; i < 4; i++)
                buildMatch(
                  legend: name,
                  rp: rp,
                  start: 1782090000 + i * 5000 + rp,
                ),
            ]))
            .toLegend(name),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RankedOverviewHighlights(
              legends: legends,
              maps: const [],
              legendMatchesFor: (_) async => const [],
              mapMatchesFor: (_) async => const [],
              onRefresh: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final pills = find.byType(RpPill);
    expect(pills, findsNWidgets(4));
    final rights = {
      for (var i = 0; i < 4; i++) tester.getTopRight(pills.at(i)).dx,
    };
    expect(rights, hasLength(1), reason: 'pill right edges: $rights');
  });
  testWidgets('the strongest and weakest legends follow the chosen measure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Axle earns most a game, Wraith most in all.
    final legends = [
      for (final (name, rp, games) in [
        ('Axle', 20, 4),
        ('Wraith', 10, 10),
        ('Bangalore', -10, 4),
        ('Octane', -20, 4),
      ])
        (RankedAgg()..addAll([
              for (var i = 0; i < games; i++)
                buildMatch(legend: name, rp: rp, start: 1782090000 + i * 5000),
            ]))
            .toLegend(name),
    ];

    Future<double Function(String)> pumpWith(BestMetric metric) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RankedOverviewHighlights(
                legends: legends,
                maps: const [],
                legendMatchesFor: (_) async => const [],
                mapMatchesFor: (_) async => const [],
                onRefresh: () async {},
                metric: metric,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (name) => tester.getTopLeft(find.text(name).first).dy;
    }

    var top = await pumpWith(BestMetric.rpPerGame);
    expect(top('Axle'), lessThan(top('Wraith')));

    top = await pumpWith(BestMetric.totalRp);
    expect(top('Wraith'), lessThan(top('Axle')));
    // The weakest two, worst first, by the same measure.
    expect(top('Octane'), lessThan(top('Bangalore')));
  });

  group('the ranking figure', () {
    // One legend and one map, each with games, kills and damage.
    RankedAgg games(String legend, String map, int rp) => RankedAgg()
      ..addAll([
        for (var i = 0; i < 4; i++)
          buildMatch(
            legend: legend,
            map: map,
            rp: rp,
            kills: 3,
            damage: 800,
            start: 1782090000 + i * 5000,
          ),
      ]);

    Future<void> pumpWith(WidgetTester tester, BestMetric metric) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RankedOverviewHighlights(
                legends: [
                  games('Axle', 'olympus_rotation', 20).toLegend('Axle'),
                ],
                maps: [
                  games(
                    'Axle',
                    'olympus_rotation',
                    20,
                  ).toMap('olympus_rotation', 'Olympus'),
                ],
                legendMatchesFor: (_) async => const [],
                mapMatchesFor: (_) async => const [],
                onRefresh: () async {},
                metric: metric,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Color? colorOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text).first).style?.color;

    testWidgets('is RP per game by default, with every stat beneath it', (
      tester,
    ) async {
      await pumpWith(tester, BestMetric.rpPerGame);

      expect(find.text('+20.0 /game'), findsOneWidget); // the legend's pill
      expect(find.text('20.0 /game'), findsOneWidget); // the map's badge
      for (final label in ['TOTAL RP', 'AVG KILLS', 'AVG DMG', 'GAMES']) {
        expect(find.text(label), findsNWidgets(2), reason: label); // each card
      }
      expect(colorOf(tester, '+20.0 /game'), AppTheme.green);
    });

    testWidgets('total RP is shown once: as the pill, not again beneath', (
      tester,
    ) async {
      await pumpWith(tester, BestMetric.totalRp);

      expect(find.text('+80 RP'), findsOneWidget); // the legend's pill
      expect(find.text('80 RP'), findsOneWidget); // the map's badge
      expect(find.text('TOTAL RP'), findsNothing);
      expect(find.text('AVG KILLS'), findsNWidgets(2));
    });

    testWidgets('average kills and damage are shown once, in the accent', (
      tester,
    ) async {
      await pumpWith(tester, BestMetric.avgKills);
      expect(find.text('3.0 kills/game'), findsNWidgets(2));
      expect(find.text('AVG KILLS'), findsNothing);
      expect(find.text('TOTAL RP'), findsNWidgets(2));
      expect(colorOf(tester, '3.0 kills/game'), AppTheme.accent);

      await pumpWith(tester, BestMetric.avgDamage);
      expect(find.text('800 dmg/game'), findsNWidgets(2));
      expect(find.text('AVG DMG'), findsNothing);
      expect(colorOf(tester, '800 dmg/game'), AppTheme.accent);
    });

    testWidgets('a total of kills, damage or the win rate keeps every stat', (
      tester,
    ) async {
      for (final (metric, text) in [
        (BestMetric.totalKills, '12 kills'),
        (BestMetric.totalDamage, '3,200 dmg'),
        (BestMetric.winRate, '100% win rate'),
      ]) {
        await pumpWith(tester, metric);

        expect(find.text(text), findsNWidgets(2), reason: '$metric');
        for (final label in ['TOTAL RP', 'AVG KILLS', 'AVG DMG', 'GAMES']) {
          expect(find.text(label), findsNWidgets(2), reason: '$metric $label');
        }
        expect(colorOf(tester, text), AppTheme.accent, reason: '$metric');
      }
    });

    testWidgets(
      'Avg RP stands in whenever a stat is dropped, in a fixed order',
      (tester) async {
        for (final metric in [
          BestMetric.totalRp,
          BestMetric.avgKills,
          BestMetric.avgDamage,
        ]) {
          await pumpWith(tester, metric);

          // Just the number, in each card.
          expect(find.text('AVG RP'), findsNWidgets(2), reason: '$metric');
          expect(find.text('+20.0'), findsNWidgets(2), reason: '$metric');
          expect(find.text('+20.0 RP'), findsNothing, reason: '$metric');

          // Total RP, Avg RP, Avg Kills, Avg Dmg, Games: those that are there.
          final xs = [
            for (final label in [
              'TOTAL RP',
              'AVG RP',
              'AVG KILLS',
              'AVG DMG',
              'GAMES',
            ])
              if (find.text(label).evaluate().isNotEmpty)
                tester.getTopLeft(find.text(label).first).dx,
          ];
          expect(xs, hasLength(4), reason: '$metric keeps four stats');
          expect(xs, [...xs]..sort(), reason: '$metric in order');
        }
      },
    );

    testWidgets('Avg RP is not added when nothing was dropped', (tester) async {
      for (final metric in [
        BestMetric.rpPerGame,
        BestMetric.totalKills,
        BestMetric.totalDamage,
        BestMetric.winRate,
      ]) {
        await pumpWith(tester, metric);

        expect(find.text('AVG RP'), findsNothing, reason: '$metric');
      }
    });

    testWidgets('a map badge for kills has no gain-or-loss arrow', (
      tester,
    ) async {
      await pumpWith(tester, BestMetric.rpPerGame);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

      await pumpWith(tester, BestMetric.avgKills);
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });
  });

  group('on a 393 dp phone', () {
    // The default test font is far wider than any real one, so the SDK's
    // Roboto is loaded for a true measure.
    setUpAll(() async {
      final root = Platform.environment['FLUTTER_ROOT'];
      if (root == null) return;
      final loader = FontLoader('Roboto');
      for (final file in [
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-Bold.ttf',
      ]) {
        final f = File('$root/bin/cache/artifacts/material_fonts/$file');
        if (f.existsSync()) {
          loader.addFont(
            Future.value(ByteData.view(f.readAsBytesSync().buffer)),
          );
        }
      }
      await loader.load();
    });

    testWidgets('a legend card shows its stats at full size, not shrunk to '
        'fit beside the pill', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // The widest figures a card is likely to carry.
      final legends = [
        for (final (name, rp, kills, damage, games) in [
          ('Wraith', -40, 1, 349, 5),
          ('Bangalore', 123, 12, 1234, 108),
        ])
          (RankedAgg()..addAll([
                for (var i = 0; i < games; i++)
                  buildMatch(
                    legend: name,
                    rp: rp,
                    kills: kills,
                    damage: damage,
                    start: 1782090000 + i * 5000,
                  ),
              ]))
              .toLegend(name),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RankedOverviewHighlights(
                legends: legends,
                maps: const [],
                legendMatchesFor: (_) async => const [],
                mapMatchesFor: (_) async => const [],
                onRefresh: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Whichever stat the default ranking repeats, Games is always there.
      final labels = find.text('GAMES');
      expect(labels, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        // A FittedBox that shrinks its child draws it smaller than it lays it
        // out: the drawn width is the laid-out width times the scale.
        final scale =
            tester.getRect(labels.at(i)).width /
            tester.getSize(labels.at(i)).width;
        expect(scale, closeTo(1, 0.001), reason: 'card $i is drawn at $scale');
      }
    });

    testWidgets('whatever it ranks by, a card keeps its stats at full size and '
        'its pill on the name line', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      RankedAgg big(String legend, String map) => RankedAgg()
        ..addAll([
          for (var i = 0; i < 108; i++)
            buildMatch(
              legend: legend,
              map: map,
              rp: i.isEven ? 25 : -12,
              kills: 12,
              damage: 2200,
              start: 1782090000 + i * 5000,
            ),
        ]);

      for (final metric in BestMetric.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RankedOverviewHighlights(
                  legends: [
                    big('Bangalore', 'olympus_rotation').toLegend('Bangalore'),
                  ],
                  maps: [
                    big(
                      'Bangalore',
                      'olympus_rotation',
                    ).toMap('olympus_rotation', "World's Edge"),
                  ],
                  legendMatchesFor: (_) async => const [],
                  mapMatchesFor: (_) async => const [],
                  onRefresh: () async {},
                  metric: metric,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: '$metric');
        final games = find.text('GAMES');
        for (var i = 0; i < 2; i++) {
          final scale =
              tester.getRect(games.at(i)).width /
              tester.getSize(games.at(i)).width;
          expect(scale, closeTo(1, 0.001), reason: '$metric card $i: $scale');
        }
      }
    });
  });
}
