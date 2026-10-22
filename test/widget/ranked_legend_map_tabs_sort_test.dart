import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/constants/stat_icons.dart';
import 'package:apexlytics/providers/entity_trend_window_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_legend_map_tabs.dart';
import 'package:apexlytics/widgets/control_pill.dart';
import 'package:apexlytics/widgets/trend_window_picker.dart'
    show DefaultTrendWindowPill;
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [await prefsOverride()],
        child: MaterialApp(home: Scaffold(body: tab)),
      ),
    );
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

  Widget legends() => RankedLegendsTab(
    rows: [
      legend('Axle', 10, 30),
      legend('Bangalore', 3, 60),
      legend('Caustic', 20, 40),
    ],
    matchesFor: (_) async => const [],
    onRefresh: () async {},
  );

  Widget maps() => RankedMapsTab(
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
        'Avg Kills',
        'Total Kills',
        'Avg Damage',
        'Total Damage',
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
    Widget withKills() => RankedLegendsTab(
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

      await choose(tester, 'Win rate', 'Total Kills');
      expect(order(tester, names).take(2), ['Axle', 'Bangalore']);

      await choose(tester, 'Total Kills', 'Avg Kills');
      expect(order(tester, names).take(2), ['Bangalore', 'Axle']);

      await choose(tester, 'Avg Kills', 'Total Damage');
      expect(order(tester, names).take(2), ['Axle', 'Bangalore']);
    });

    testWidgets('a legend with no kills reported goes last, not first', (
      tester,
    ) async {
      await pump(tester, withKills());

      await choose(tester, 'Total RP', 'Avg Kills');

      expect(order(tester, ['Axle', 'Bangalore', 'Caustic']).last, 'Caustic');
    });

    testWidgets('the pill shows the order chosen, with its icon', (
      tester,
    ) async {
      await pump(tester, withKills());

      await choose(tester, 'Total RP', 'Avg Kills');

      expect(find.widgetWithText(ControlPill, 'Avg Kills'), findsOneWidget);
      expect(find.byIcon(StatIcons.avgKills), findsOneWidget);
    });
  });

  group('the Trend window pill on the tabs', () {
    late SharedPreferences prefs;

    Future<ProviderContainer> pumpScoped(
      WidgetTester tester,
      Widget tab,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: tab)),
        ),
      );
      await tester.pump();
      return container;
    }

    // The pill's own label: the sheet has its own "Auto" and counts too.
    Finder pillLabel(String label) => find.descendant(
      of: find.byType(DefaultTrendWindowPill),
      matching: find.text(label),
    );

    for (final (name, tab) in [('Legends', legends), ('Maps', maps)]) {
      testWidgets('is on the $name tab, saying what it is and its value', (
        tester,
      ) async {
        await pumpScoped(tester, tab());

        expect(find.text('Trend window:'), findsOneWidget);
        expect(pillLabel('Auto'), findsOneWidget);
        expect(find.byIcon(Icons.trending_up), findsOneWidget);
        // At the left, level with Sort at the right: no row of its own.
        final trends = tester.getTopLeft(find.text('Trend window:'));
        final sort = tester.getTopLeft(find.text('Sort:'));
        expect(trends.dx, lessThan(sort.dx));
        expect((trends.dy - sort.dy).abs(), lessThan(24));
      });
    }

    testWidgets('opens a sheet of Auto and four game counts, Auto lit', (
      tester,
    ) async {
      await pumpScoped(tester, legends());

      await tester.tap(pillLabel('Auto'));
      await tester.pumpAndSettle();

      expect(find.text('Trend window'), findsOneWidget);
      final labels = [
        'Auto',
        'Last 10 games',
        'Last 25 games',
        'Last 50 games',
        'Last 100 games',
      ];
      // The counts, then a row to type one in.
      expect(find.byType(ListTile), findsNWidgets(labels.length + 1));
      expect(find.text('Custom…'), findsOneWidget);
      double top(String l) => tester.getTopLeft(inSheet(l)).dy;
      expect([...labels]..sort((a, b) => top(a).compareTo(top(b))), labels);
      expect(find.byIcon(Icons.check), findsOneWidget);
      final lit = tester.widget<Text>(inSheet('Auto'));
      expect(lit.style?.color, AppTheme.accent);
      // No "All": there is nothing for it to compare against.
      expect(find.text('All'), findsNothing);
      expect(find.textContaining('Auto uses about a quarter'), findsOneWidget);
      expect(find.textContaining('on its page'), findsOneWidget);
    });

    group('a count typed in', () {
      Future<void> openField(WidgetTester tester) async {
        await tester.tap(pillLabel('Auto'));
        await tester.pumpAndSettle();
        await tester.tap(inSheet('Custom…'));
        await tester.pumpAndSettle();
      }

      Future<void> type(WidgetTester tester, String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump();
      }

      Finder use() => find.widgetWithText(TextButton, 'Use');

      testWidgets('asks for 5 to 1,000 games', (tester) async {
        await pumpScoped(tester, legends());
        await openField(tester);

        expect(find.text('Custom trend window'), findsOneWidget);
        expect(find.textContaining('5 to 1,000'), findsOneWidget);
        // Nothing yet: nothing wrong either, but nothing to use.
        expect(tester.widget<TextButton>(use()).onPressed, isNull);
      });

      testWidgets('keeps one in range, shows it on the pill, and lights the '
          'row', (tester) async {
        final container = await pumpScoped(tester, legends());
        await openField(tester);

        await type(tester, '37');
        await tester.tap(use());
        await tester.pumpAndSettle();

        expect(container.read(entityTrendWindowProvider), 37);
        expect(prefs.getInt(PrefsKeys.entityTrendGames), 37);
        expect(pillLabel('37 games'), findsOneWidget);

        await tester.tap(pillLabel('37 games'));
        await tester.pumpAndSettle();
        final lit = tester.widget<Text>(inSheet('Custom (37 games)'));
        expect(lit.style?.color, AppTheme.accent);
        // It starts the field at what was typed.
        await tester.tap(inSheet('Custom (37 games)'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '37',
        );
      });

      for (final (text, why) in [('4', 'below 5'), ('1001', 'above 1,000')]) {
        testWidgets('does not take $text, $why', (tester) async {
          final container = await pumpScoped(tester, legends());
          await openField(tester);

          await type(tester, text);

          expect(find.text('Enter 5 to 1,000'), findsOneWidget);
          expect(tester.widget<TextButton>(use()).onPressed, isNull);
          await tester.tap(use());
          await tester.pump();
          expect(container.read(entityTrendWindowProvider), 0);
        });
      }

      testWidgets('a count of a thousand reads 1,000 on the pill and the row', (
        tester,
      ) async {
        final container = await pumpScoped(tester, legends());
        await container.read(entityTrendWindowProvider.notifier).set(1000);
        await tester.pump();

        expect(pillLabel('1,000 games'), findsOneWidget);
        expect(find.text('1000 games'), findsNothing);

        await tester.tap(pillLabel('1,000 games'));
        await tester.pumpAndSettle();
        expect(find.text('Custom (1,000 games)'), findsOneWidget);
      });

      testWidgets('takes digits only', (tester) async {
        await pumpScoped(tester, legends());
        await openField(tester);

        await type(tester, '1a2.5-');

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '125',
        );
      });

      testWidgets('Cancel changes nothing', (tester) async {
        final container = await pumpScoped(tester, legends());
        await openField(tester);

        await type(tester, '40');
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(container.read(entityTrendWindowProvider), 0);
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('choosing a count keeps it, closes the sheet, and is lit '
        'next time', (tester) async {
      final container = await pumpScoped(tester, maps());

      await tester.tap(pillLabel('Auto'));
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Last 25 games'));
      await tester.pumpAndSettle();

      expect(container.read(entityTrendWindowProvider), 25);
      expect(prefs.getInt(PrefsKeys.entityTrendGames), 25);
      expect(find.byType(ListTile), findsNothing);
      // The pill now says so.
      expect(pillLabel('25 games'), findsOneWidget);
      expect(pillLabel('Auto'), findsNothing);

      await tester.tap(pillLabel('25 games'));
      await tester.pumpAndSettle();
      final lit = tester.widget<Text>(inSheet('Last 25 games'));
      expect(lit.style?.color, AppTheme.accent);
      expect(
        tester.widget<Text>(inSheet('Auto')).style?.color,
        isNot(AppTheme.accent),
      );
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
