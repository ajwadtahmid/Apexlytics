import 'package:apexlytics/screens/ranked/widgets/ranked_slot_chart.dart';
import 'package:apexlytics/screens/ranked/widgets/compare_row.dart';
import 'package:apexlytics/utils/ranked/slot_compare.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Slot _s(int slot, int games, int netRp) =>
    (slot: slot, games: games, netRp: netRp);

void main() {
  Future<void> pump(WidgetTester tester, Widget chart) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: chart)),
      ),
    );
    await tester.pump();
  }

  BarChartData data(WidgetTester tester) =>
      tester.widget<BarChart>(find.byType(BarChart)).data;

  // Split A played noon and 9 PM; split B played 9 PM and 11 PM.
  final a = [_s(12, 4, -8), _s(21, 6, 30)];
  final b = [_s(21, 5, 5), _s(23, 8, 40)];

  Widget hours() =>
      RankedSlotChart.hours(nameA: 'Split 1', nameB: 'Split 2', a: a, b: b);

  testWidgets('the axis covers the hours played, noon to 11 PM here, and '
      'the two splits line up', (tester) async {
    await pump(tester, hours());

    final groups = data(tester).barGroups;
    expect(groups, hasLength(12));
    // 9 PM is the tenth column for both, each with a bar per split.
    expect(groups[9].barRods, hasLength(2));
    expect(groups[9].barRods[0].toY, 6);
    expect(groups[9].barRods[1].toY, 5);
    // An hour in between that neither played is an empty column.
    expect(groups[1].barRods.map((r) => r.toY), [0, 0]);
    expect(find.text('12 PM'), findsOneWidget);
    expect(find.text('12 AM'), findsNothing);
  });

  testWidgets('a late night runs across midnight on one axis', (tester) async {
    await pump(
      tester,
      RankedSlotChart.hours(
        nameA: 'Split 1',
        nameB: 'Split 2',
        a: [_s(22, 4, 10), _s(23, 4, 10)],
        b: [_s(0, 5, 10), _s(1, 3, 10)],
      ),
    );

    // 10 PM, 11 PM, 12 AM, 1 AM.
    final groups = data(tester).barGroups;
    expect(groups, hasLength(4));
    expect(groups[1].barRods[0].toY, 4); // 11 PM, split 1
    expect(groups[2].barRods[1].toY, 5); // 12 AM, split 2
  });

  testWidgets('the switch changes the bars from games to RP per game', (
    tester,
  ) async {
    await pump(tester, hours());

    await tester.tap(find.text('RP / game'));
    await tester.pump();

    final groups = data(tester).barGroups;
    expect(groups[0].barRods[0].toY, -2); // noon: -8 over 4 games
    expect(groups[9].barRods[0].toY, 5); // 9 PM: 30 over 6
    expect(groups[11].barRods[1].toY, 5); // 11 PM: 40 over 8
    // Room below zero for the losing hour.
    expect(data(tester).minY, lessThan(-2));
  });

  testWidgets('both splits share one scale', (tester) async {
    await pump(tester, hours());

    // Split B's 8 games at 11 PM is the tallest bar in either split.
    expect(data(tester).maxY, 8 * 1.25);
  });

  testWidgets('says where the best and weakest hour went', (tester) async {
    await pump(tester, hours());

    expect(find.text('Best hour moved from 9 PM to 11 PM'), findsOneWidget);
    // A's weakest is noon (-2 a game); B's is 9 PM (+1 a game).
    expect(find.text('Weakest hour moved from 12 PM to 9 PM'), findsOneWidget);
  });

  testWidgets('days run Monday to Sunday on one axis', (tester) async {
    await pump(
      tester,
      RankedSlotChart.days(
        nameA: 'Split 1',
        nameB: 'Split 2',
        a: [_s(6, 5, 20), _s(7, 4, -4)],
        b: [_s(6, 6, 30), _s(2, 3, 9)],
      ),
    );

    expect(data(tester).barGroups, hasLength(7));
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);
    expect(find.text('Best day stayed Sat'), findsOneWidget);
  });

  testWidgets('shows nothing when neither split has any games', (tester) async {
    await pump(
      tester,
      RankedSlotChart.days(
        nameA: 'Split 1',
        nameB: 'Split 2',
        a: const [],
        b: const [],
      ),
    );

    expect(find.byType(BarChart), findsNothing);
  });

  group('one period', () {
    // Noon, 9 PM and 11 PM: a gain, a loss and a gain.
    final played = [_s(12, 6, 30), _s(21, 5, -20), _s(23, 4, 8)];

    Widget hoursOnly() => RankedSlotChart.hours(a: played);

    testWidgets('has one bar a column, green for a gain and red for a loss', (
      tester,
    ) async {
      await pump(tester, hoursOnly());

      final groups = data(tester).barGroups;
      expect(groups, hasLength(12)); // noon to 11 PM
      expect(groups.every((g) => g.barRods.length == 1), isTrue);
      expect(groups[0].barRods.single.color, AppTheme.green);
      expect(groups[9].barRods.single.color, AppTheme.red);
      expect(groups[11].barRods.single.color, AppTheme.green);
    });

    testWidgets('shows the hours played and no key or best and worst lines', (
      tester,
    ) async {
      await pump(tester, hoursOnly());

      expect(find.text('12 PM'), findsOneWidget);
      expect(find.text('12 AM'), findsNothing);
      expect(find.textContaining('Best hour'), findsNothing);
      expect(find.textContaining('Weakest hour'), findsNothing);
      expect(find.byType(CompareKey), findsNothing);
    });

    testWidgets('the switch shows RP per game, and loss hours go below zero', (
      tester,
    ) async {
      await pump(tester, hoursOnly());

      await tester.tap(find.text('RP / game'));
      await tester.pump();

      final groups = data(tester).barGroups;
      expect(groups[0].barRods.single.toY, 5); // 30 over 6
      expect(groups[9].barRods.single.toY, -4); // -20 over 5
      expect(data(tester).minY, lessThan(-4));
    });

    testWidgets(
      'fades an hour with too few games in the RP view, and says so',
      (tester) async {
        await pump(
          tester,
          RankedSlotChart.hours(a: [..._played(), _s(15, 2, 40)]),
        );
        expect(find.textContaining('Faded bars'), findsNothing);

        await tester.tap(find.text('RP / game'));
        await tester.pump();

        final groups = data(tester).barGroups;
        expect(
          groups[3].barRods.single.color!.a,
          lessThan(0.5),
        ); // 3 PM: 2 games
        expect(groups[0].barRods.single.color!.a, 1); // noon: 6 games
        expect(find.text('Faded bars have under 3 games.'), findsOneWidget);
      },
    );

    testWidgets('days show Monday to Sunday', (tester) async {
      await pump(tester, RankedSlotChart.days(a: [_s(2, 5, 20), _s(6, 4, -8)]));

      expect(data(tester).barGroups, hasLength(7));
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('one hour of play is not a chart', (tester) async {
      await pump(tester, RankedSlotChart.hours(a: [_s(12, 6, 30)]));

      expect(find.byType(BarChart), findsNothing);
    });
  });
}

List<Slot> _played() => [_s(12, 6, 30), _s(21, 5, -20), _s(23, 4, 8)];
