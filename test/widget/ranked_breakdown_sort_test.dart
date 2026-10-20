import 'package:apexlytics/constants/stat_icons.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_breakdown_tables.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Legends and Maps tabs' "Sort:" pill opens a sheet of orders, as the
/// Legends tab of the trackers does, rather than cycling on each tap.
void main() {
  // Three different orders: by total RP B, C, A; by games C, A, B; by RP per
  // game B, A, C.
  LegendBreakdown legend(
    String name,
    int games,
    int rp, {
    int kills = 0,
    int? killsGames,
    int damage = 0,
    int wins = 0,
    int losses = 0,
  }) => LegendBreakdown(
    legend: name,
    games: games,
    totalRp: rp,
    totalKills: kills,
    totalDamage: damage,
    killsGames: killsGames ?? 0,
    damageGames: killsGames ?? 0,
    totalLengthSecs: 0,
    wins: wins,
    losses: losses,
  );
  MapBreakdown map(String key, String name, int games, int rp) => MapBreakdown(
    mapKey: key,
    displayName: name,
    games: games,
    totalRp: rp,
    totalKills: 0,
    totalDamage: 0,
    killsGames: 0,
    damageGames: 0,
    totalLengthSecs: 0,
    wins: 0,
    losses: 0,
  );

  Future<void> pump(WidgetTester tester, Widget tab) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: tab)));
    await tester.pump();
  }

  /// The names in the order they sit down the page.
  List<String> order(WidgetTester tester, List<String> names) =>
      [...names]..sort(
        (a, b) => tester
            .getTopLeft(find.text(a).first)
            .dy
            .compareTo(tester.getTopLeft(find.text(b).first).dy),
      );

  /// An order's row in the sheet; the cards carry an "Avg RP" label too.
  Finder inSheet(String label) =>
      find.descendant(of: find.byType(ListTile), matching: find.text(label));

  Widget legends() => RankedLegendBreakdown(
    rows: [
      legend('Axle', 10, 30),
      legend('Bangalore', 3, 60),
      legend('Caustic', 20, 40),
    ],
    matchesFor: (_) async => const [],
    onRefresh: () async {},
  );

  Widget maps() => RankedMapBreakdown(
    rows: [
      map('olympus_rotation', 'Olympus', 10, 30),
      map('storm_point_rotation', 'Storm Point', 3, 60),
      map('broken_moon_rotation', 'Broken Moon', 20, 40),
    ],
    matchesFor: (_) async => const [],
    onRefresh: () async {},
  );

  group('the Legends tab', () {
    testWidgets('starts on total RP, and the pill says so', (tester) async {
      await pump(tester, legends());

      expect(find.text('Sort:'), findsOneWidget);
      expect(find.text('Total RP'), findsOneWidget);
      expect(order(tester, ['Axle', 'Bangalore', 'Caustic']), [
        'Bangalore',
        'Caustic',
        'Axle',
      ]);
    });

    testWidgets('tapping the pill lists the orders, and does not cycle', (
      tester,
    ) async {
      await pump(tester, legends());

      await tester.tap(find.text('Total RP'));
      await tester.pumpAndSettle();

      expect(find.text('Sort legends by'), findsOneWidget);
      // Down the sheet in this order.
      final labels = [
        'Total RP',
        'Avg RP',
        'Games',
        'Win rate',
        'Avg kills',
        'Total kills',
        'Avg damage',
        'Total damage',
      ];
      expect(find.byType(ListTile), findsNWidgets(labels.length));
      double top(String l) => tester.getTopLeft(inSheet(l)).dy;
      expect([...labels]..sort((a, b) => top(a).compareTo(top(b))), labels);
      // The one in use is lit with a tick.
      expect(find.byIcon(Icons.check), findsOneWidget);
      final lit = tester.widget<Text>(find.text('Total RP').last);
      expect(lit.style?.color, AppTheme.accent);
    });

    testWidgets('choosing an order applies it, and closes the sheet', (
      tester,
    ) async {
      await pump(tester, legends());

      await tester.tap(find.text('Total RP'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();

      expect(find.text('Sort legends by'), findsNothing);
      expect(order(tester, ['Axle', 'Bangalore', 'Caustic']), [
        'Caustic',
        'Axle',
        'Bangalore',
      ]);
      expect(find.text('Games'), findsOneWidget); // the pill

      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Avg RP'));
      await tester.pumpAndSettle();

      expect(order(tester, ['Axle', 'Bangalore', 'Caustic']), [
        'Bangalore',
        'Axle',
        'Caustic',
      ]);
    });
  });

  group('the orders beyond RP and games', () {
    // Axle 2 kills a game and 20 in all; Bangalore 4 a game and 12; Caustic
    // reported none. Win rates: Caustic 3 of 4, Axle 1 of 2, Bangalore 1 of 4.
    Widget withKills() => RankedLegendBreakdown(
      rows: [
        legend(
          'Axle',
          10,
          30,
          kills: 20,
          killsGames: 10,
          damage: 5000,
          wins: 1,
          losses: 1,
        ),
        legend(
          'Bangalore',
          3,
          60,
          kills: 12,
          killsGames: 3,
          damage: 1500,
          wins: 1,
          losses: 3,
        ),
        legend('Caustic', 20, 40, wins: 3, losses: 1),
      ],
      matchesFor: (_) async => const [],
      onRefresh: () async {},
    );

    Future<void> choose(WidgetTester tester, String from, String to) async {
      await tester.tap(find.text(from).first);
      await tester.pumpAndSettle();
      await tester.tap(inSheet(to));
      await tester.pumpAndSettle();
    }

    testWidgets('sort by win rate, kills and damage, biggest first', (
      tester,
    ) async {
      await pump(tester, withKills());
      final names = ['Axle', 'Bangalore', 'Caustic'];

      await choose(tester, 'Total RP', 'Win rate');
      expect(order(tester, names), ['Caustic', 'Axle', 'Bangalore']);

      await choose(tester, 'Win rate', 'Total kills');
      expect(order(tester, names).take(2), ['Axle', 'Bangalore']);

      await choose(tester, 'Total kills', 'Avg kills');
      expect(order(tester, names).take(2), ['Bangalore', 'Axle']);

      await choose(tester, 'Avg kills', 'Total damage');
      expect(order(tester, names).take(2), ['Axle', 'Bangalore']);
    });

    testWidgets('a legend with no kills reported goes last, not first', (
      tester,
    ) async {
      await pump(tester, withKills());

      await choose(tester, 'Total RP', 'Avg kills');

      expect(order(tester, ['Axle', 'Bangalore', 'Caustic']).last, 'Caustic');
    });

    testWidgets('the pill shows the order chosen, with its icon', (
      tester,
    ) async {
      await pump(tester, withKills());

      await choose(tester, 'Total RP', 'Avg kills');

      expect(find.text('Avg kills'), findsOneWidget);
      expect(find.byIcon(StatIcons.avgKills), findsOneWidget);
    });
  });

  group('the Maps tab', () {
    testWidgets('has the same sheet, titled for maps', (tester) async {
      await pump(tester, maps());

      await tester.tap(find.text('Total RP'));
      await tester.pumpAndSettle();

      expect(find.text('Sort maps by'), findsOneWidget);
      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();

      expect(order(tester, ['Olympus', 'Storm Point', 'Broken Moon']), [
        'Broken Moon',
        'Olympus',
        'Storm Point',
      ]);
    });
  });
}
