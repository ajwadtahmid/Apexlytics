import 'package:apexlytics/screens/ranked/widgets/compare_row.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  FontWeight weightOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.fontWeight!;

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  group('which side is ahead', () {
    test('is the second when the change is up, the first when it is down', () {
      expect(const CompareRow('Win', '40%', '50%', delta: 10).winner, 1);
      expect(const CompareRow('Win', '50%', '40%', delta: -10).winner, -1);
    });

    test('is reversed where more is worse', () {
      expect(
        const CompareRow('Games', '9', '12', delta: 3, invert: true).winner,
        -1,
      );
    });

    test('is nobody when level as shown, or when there is no change', () {
      expect(const CompareRow('Kills', '1.0', '1.0', delta: 0.04).winner, 0);
      expect(
        const CompareRow(
          'Net',
          '+3',
          '+3',
          delta: 0,
          integerDelta: true,
        ).winner,
        0,
      );
      expect(const CompareRow('Games', '9', '12').winner, 0);
    });
  });

  testWidgets('the better value is bold and the other is plain', (
    tester,
  ) async {
    await pump(tester, const CompareRow('Win rate', '40%', '55%', delta: 15));

    expect(weightOf(tester, '55%'), FontWeight.w800);
    expect(weightOf(tester, '40%'), FontWeight.w500);
    expect(colorOf(tester, '55%'), AppTheme.textPrimary);
    expect(colorOf(tester, '40%'), AppTheme.textPrimary);
  });

  testWidgets('a row with no verdict keeps both values the same', (
    tester,
  ) async {
    await pump(tester, const CompareRow('Games', '9', '12'));

    expect(colorOf(tester, '9'), AppTheme.textPrimary);
    expect(colorOf(tester, '12'), AppTheme.textPrimary);
    expect(weightOf(tester, '9'), weightOf(tester, '12'));
  });

  Color? chipOf(WidgetTester tester, String text) {
    final box = tester.widget<Container>(
      find
          .ancestor(of: find.text(text), matching: find.byType(Container))
          .first,
    );
    return (box.decoration as BoxDecoration).color;
  }

  testWidgets('only the leading value sits in a chip, in its side\'s colour', (
    tester,
  ) async {
    await pump(tester, const CompareRow('Win rate', '40%', '55%', delta: 15));

    expect(chipOf(tester, '40%'), isNull);
    final chip = chipOf(tester, '55%')!;
    expect(chip.toARGB32() & 0xFFFFFF, kCompareColorB.toARGB32() & 0xFFFFFF);
    expect(chip.a, lessThan(0.5));
  });

  testWidgets('a level or neutral row has no chip', (tester) async {
    await pump(tester, const CompareRow('Games', '9', '12'));

    expect(chipOf(tester, '9'), isNull);
    expect(chipOf(tester, '12'), isNull);
  });

  group('the table', () {
    CompareTable table(List<CompareRow> rows) =>
        CompareTable(nameA: 'Axle', nameB: 'Wraith', rows: rows);

    testWidgets('names the side leading on most rows', (tester) async {
      await pump(
        tester,
        table(const [
          CompareRow('Win rate', '40%', '55%', delta: 15),
          CompareRow('Kills', '2.0', '3.0', delta: 1),
          CompareRow('Dmg', '900', '700', delta: -200),
          // Not good or bad, so not counted.
          CompareRow('Games', '9', '12'),
        ]),
      );

      expect(find.text('Wraith leads on 2 of 3 stats'), findsOneWidget);
      // In the leading side's colour.
      expect(
        tester
            .widget<Text>(find.text('Wraith leads on 2 of 3 stats'))
            .style!
            .color,
        kCompareColorB,
      );
    });

    testWidgets('says level when each leads on as many', (tester) async {
      await pump(
        tester,
        table(const [
          CompareRow('Win rate', '40%', '55%', delta: 15),
          CompareRow('Dmg', '900', '700', delta: -200),
        ]),
      );

      expect(find.text('Level: 1 stat each'), findsOneWidget);
    });

    testWidgets('says nothing when no row has a verdict', (tester) async {
      await pump(tester, table(const [CompareRow('Games', '9', '12')]));

      expect(find.textContaining('leads on'), findsNothing);
      expect(find.textContaining('Level'), findsNothing);
      // The key still says which colour is which.
      expect(find.text('Axle'), findsOneWidget);
      expect(find.text('Wraith'), findsOneWidget);
    });
  });

  group('as a head-to-head, with the change measured from the first side', () {
    test('the first side leads on a positive change', () {
      const ahead = CompareRow(
        'RP',
        '7,000',
        '5,600',
        delta: 1400,
        deltaFromFirst: true,
      );
      const behind = CompareRow(
        'RP',
        '5,600',
        '7,000',
        delta: -1400,
        deltaFromFirst: true,
      );

      expect(ahead.winner, -1);
      expect(behind.winner, 1);
    });

    test('fewer is better where the row is inverted', () {
      const fewer = CompareRow(
        'RP needed',
        '450',
        '650',
        delta: -200,
        invert: true,
        deltaFromFirst: true,
      );

      expect(fewer.winner, -1);
    });

    test('is nobody when level, as it is the other way round', () {
      const level = CompareRow(
        'Level',
        '100',
        '100',
        delta: 0,
        integerDelta: true,
        deltaFromFirst: true,
      );

      expect(level.winner, 0);
    });

    testWidgets('colours a lead green and a deficit red', (tester) async {
      await pump(
        tester,
        const Column(
          children: [
            CompareRow('Up', '9', '5', delta: 4, deltaFromFirst: true),
            CompareRow('Down', '5', '9', delta: -4, deltaFromFirst: true),
          ],
        ),
      );

      expect(colorOf(tester, '+4.0'), AppTheme.green);
      expect(colorOf(tester, '-4.0'), AppTheme.red);
    });

    testWidgets('a change that is nothing as shown is muted, not green', (
      tester,
    ) async {
      await pump(
        tester,
        const CompareRow(
          'Level',
          '100',
          '100',
          delta: 0,
          integerDelta: true,
          deltaFromFirst: true,
        ),
      );

      expect(colorOf(tester, '+0'), AppTheme.muted);
    });

    testWidgets('shows more decimals when asked, so a small gap is not lost', (
      tester,
    ) async {
      const row = CompareRow(
        'Revive Rate',
        '0.13',
        '0.09',
        delta: 0.04,
        decimals: 2,
        deltaFromFirst: true,
      );
      await pump(tester, row);

      expect(find.text('+0.04'), findsOneWidget);
      expect(row.winner, -1);
      // At one decimal the same gap would have read as level.
      expect(
        const CompareRow(
          'Revive Rate',
          '0.13',
          '0.09',
          delta: 0.04,
          deltaFromFirst: true,
        ).winner,
        0,
      );
    });

    testWidgets('the table says "You lead" when the first side is you', (
      tester,
    ) async {
      await pump(
        tester,
        const CompareTable(
          nameA: 'You',
          nameB: 'Rival',
          firstIsYou: true,
          colorA: AppTheme.accent,
          colorB: AppTheme.muted,
          rows: [
            CompareRow('RP', '9', '5', delta: 4, deltaFromFirst: true),
            CompareRow('Lvl', '9', '5', delta: 4, deltaFromFirst: true),
            CompareRow('Win', '5', '9', delta: -4, deltaFromFirst: true),
          ],
        ),
      );

      expect(find.text('You lead on 2 of 3 stats'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('You lead on 2 of 3 stats')).style!.color,
        AppTheme.accent,
      );
    });
  });
}
