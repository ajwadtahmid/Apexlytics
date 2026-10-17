import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/ranked_session_detail_screen.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/rp_pill.dart';
import 'package:apexlytics/widgets/surface_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// One session of games played in order: each is (legend, RP).
RankedSession _session(List<(String, int)> games) => sessionize([
  for (final (i, (legend, rp)) in games.indexed)
    buildMatch(
      legend: legend,
      rp: rp,
      kills: 2,
      damage: 500,
      start: 1782090000 + i * 1500,
    ),
]).single;

void main() {
  Future<void> pump(WidgetTester tester, RankedSession session) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: RankedSessionDetailScreen(
            session: session,
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // +20, +10, -15, -20, +30: up to +30, down to -5, back up to +25.
  final mixed = _session([
    ('Axle', 20),
    ('Axle', 10),
    ('Loba', -15),
    ('Loba', -20),
    ('Axle', 30),
  ]);

  testWidgets('sums the session up', (tester) async {
    await pump(tester, mixed);

    expect(find.text('+25 RP'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // games
    // Wins and losses, in two colours.
    expect(find.text('3–2', findRichText: true), findsOneWidget);
    expect(find.text('10'), findsOneWidget); // kills: 2 a game
    expect(find.text('2,500'), findsOneWidget); // damage
  });

  testWidgets('shows the RP through the games and marks the worst fall', (
    tester,
  ) async {
    await pump(tester, mixed);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots.map((s) => s.y), [
      0,
      20,
      30,
      15,
      -5,
      25,
    ]);
    // The gain is shaded green, up to the +30 peak after game 2, and the drop
    // red, down through games 3 and 4.
    final bands = chart.data.rangeAnnotations.verticalRangeAnnotations;
    expect([for (final b in bands) (b.x1, b.x2)], [(0, 2), (2, 4)]);
    expect(bands[0].color!.g, greaterThan(bands[0].color!.r));
    expect(bands[1].color!.r, greaterThan(bands[1].color!.g));
    expect(find.text('Biggest drop: -35 RP over games 3–4'), findsOneWidget);
    // Up from the start to the +30 peak after game 2.
    expect(find.text('Biggest gain: +30 RP over games 1–2'), findsOneWidget);
  });

  testWidgets('wins are green and losses red', (tester) async {
    await pump(tester, mixed);

    final record = tester.widget<RichText>(
      find.text('3–2', findRichText: true),
    );
    final parts = <TextSpan>[];
    record.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) parts.add(span);
      return true;
    });
    expect(parts.map((p) => p.text), ['3', '–', '2']);
    expect(parts[0].style!.color, AppTheme.green);
    expect(parts[2].style!.color, AppTheme.red);
  });

  testWidgets('shows the average RP a game, green when it gained', (
    tester,
  ) async {
    await pump(tester, mixed); // +25 over five games

    expect(find.text('avg RP/game'), findsOneWidget);
    final avg = tester.widget<Text>(find.text('+5.0'));
    expect(avg.style!.color, AppTheme.green);
    expect(find.text('longest gap'), findsNothing);
  });

  testWidgets('the average RP a game is red when it lost', (tester) async {
    await pump(tester, _session([('Axle', -10), ('Axle', -20), ('Axle', 6)]));

    final avg = tester.widget<Text>(find.text('-8.0'));
    expect(avg.style!.color, AppTheme.red);
  });

  testWidgets('a session that never falls marks no drop', (tester) async {
    await pump(tester, _session([('Axle', 10), ('Axle', 20), ('Axle', 5)]));

    expect(find.textContaining('Biggest drop'), findsNothing);
    expect(find.text('Biggest gain: +35 RP over games 1–3'), findsOneWidget);
    // Only the gain is shaded.
    final bands = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .rangeAnnotations
        .verticalRangeAnnotations;
    expect([for (final b in bands) (b.x1, b.x2)], [(0, 3)]);
  });

  testWidgets('a session that never rises marks no gain', (tester) async {
    await pump(tester, _session([('Axle', -10), ('Axle', -20)]));

    expect(find.textContaining('Biggest gain'), findsNothing);
    expect(find.textContaining('Biggest drop'), findsOneWidget);
    final bands = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .rangeAnnotations
        .verticalRangeAnnotations;
    expect([for (final b in bands) (b.x1, b.x2)], [(0, 2)]);
  });

  group('the curve\'s colours', () {
    LineChartBarData line(WidgetTester tester) => tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineBarsData
        .single;

    Color dot(LineChartBarData bar, double y) {
      final painter =
          bar.dotData.getDotPainter(FlSpot(1, y), 0, bar, 0)
              as FlDotCirclePainter;
      return painter.color;
    }

    testWidgets('change at the baseline when the session crosses it', (
      tester,
    ) async {
      await pump(tester, mixed); // up to +30, down to -5, back up to +25

      final bar = line(tester);
      final gradient = bar.gradient! as LinearGradient;
      expect(gradient.colors, [
        AppTheme.green,
        AppTheme.green,
        AppTheme.red,
        AppTheme.red,
      ]);
      // The baseline is 30 of the 35 RP between the highest and lowest points,
      // measured down from the top.
      expect(gradient.stops, [0, 30 / 35, 30 / 35, 1]);
    });

    testWidgets('each dot takes the colour of its side of the baseline', (
      tester,
    ) async {
      await pump(tester, mixed);
      final bar = line(tester);

      expect(dot(bar, 20), AppTheme.green);
      expect(dot(bar, 0), AppTheme.green);
      expect(dot(bar, -5), AppTheme.red);
      // The last game gained the most from the low, but is back above zero.
      expect(dot(bar, 25), AppTheme.green);
    });

    testWidgets('a game that gains but stays below the baseline stays red', (
      tester,
    ) async {
      // +55, then down to -137, then +123: the last total is still -14.
      await pump(
        tester,
        _session([
          ('Axle', 55),
          ('Axle', -96),
          ('Axle', -48),
          ('Axle', -48),
          ('Axle', 123),
        ]),
      );
      final bar = line(tester);

      expect(dot(bar, 55), AppTheme.green);
      expect(dot(bar, -14), AppTheme.red);
    });

    testWidgets('a session that stays above the baseline is green throughout', (
      tester,
    ) async {
      await pump(tester, _session([('Axle', 10), ('Axle', 20), ('Axle', 5)]));
      final bar = line(tester);

      expect(bar.gradient, isNull);
      expect(bar.color, AppTheme.green);
    });

    testWidgets('a session that stays below it is red throughout', (
      tester,
    ) async {
      await pump(tester, _session([('Axle', -10), ('Axle', -20)]));
      final bar = line(tester);

      expect(bar.gradient, isNull);
      expect(bar.color, AppTheme.red);
    });
  });

  testWidgets('shows how each legend did, best first', (tester) async {
    await pump(tester, mixed);

    expect(find.text('BY LEGEND'), findsOneWidget);
    // The game rows below name legends too, so look inside this card.
    final card = find
        .ancestor(
          of: find.text('BY LEGEND'),
          matching: find.byType(SurfaceCard),
        )
        .first;
    double top(String legend) => tester
        .getTopLeft(find.descendant(of: card, matching: find.text(legend)))
        .dy;
    expect(top('Axle'), lessThan(top('Loba'))); // +60 over -35
    expect(find.text('+60 RP'), findsOneWidget);
    expect(find.text('-35 RP'), findsOneWidget);
  });

  testWidgets('one legend needs no breakdown', (tester) async {
    await pump(tester, _session([('Axle', 10), ('Axle', -5), ('Axle', 20)]));

    expect(find.text('BY LEGEND'), findsNothing);
  });

  testWidgets('a single game has no curve', (tester) async {
    await pump(tester, _session([('Axle', 10)]));

    expect(find.byType(LineChart), findsNothing);
    expect(find.text('GAMES · 1'), findsOneWidget);
  });

  testWidgets('lists the session\'s games on the page itself', (tester) async {
    await pump(tester, mixed);

    expect(find.text('GAMES · 5'), findsOneWidget);
    // A game row carries its RP in a pill; nothing else on the page does.
    expect(find.byType(RpPill), findsNWidgets(5));
    // No extra step to see them, and no session title repeating the summary.
    expect(find.textContaining('All 5 games'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('the games follow the cards, in one scroll', (tester) async {
    await pump(tester, mixed);

    final curve = tester.getTopLeft(find.text('RP THROUGH THE SESSION')).dy;
    final heading = tester.getTopLeft(find.text('GAMES · 5')).dy;
    final firstGame = tester.getTopLeft(find.byType(RpPill).first).dy;
    expect(curve, lessThan(heading));
    expect(heading, lessThan(firstGame));
  });
}
