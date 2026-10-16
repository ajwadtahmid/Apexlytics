import 'package:apexlytics/widgets/win_loss_stat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, int wins, int losses) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WinLossStat(wins: wins, losses: losses)),
        ),
      );

  testWidgets('the win rate keeps one decimal instead of rounding to 40%', (
    tester,
  ) async {
    await pump(tester, 1997, 3003); // 39.94%

    expect(find.textContaining('39.9%', findRichText: true), findsOneWidget);
    expect(find.textContaining('40%', findRichText: true), findsNothing);
  });

  testWidgets('no decided games shows a dash', (tester) async {
    await pump(tester, 0, 0);

    expect(find.textContaining('—', findRichText: true), findsOneWidget);
  });

  testWidgets('the label and rate are centred', (tester) async {
    await pump(tester, 3, 1);

    final column = tester.widget<Column>(
      find.descendant(
        of: find.byType(WinLossStat),
        matching: find.byType(Column),
      ),
    );
    expect(column.crossAxisAlignment, CrossAxisAlignment.center);
  });
}
