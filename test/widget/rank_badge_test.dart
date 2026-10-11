import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/constants/rank_constants.dart';
import 'package:apexlytics/widgets/rank_badge.dart';

void main() {
  Future<void> pump(WidgetTester tester, String? path) => tester.pumpWidget(
    MaterialApp(
      home: Center(child: RankBadge(assetPath: path, size: 36)),
    ),
  );

  testWidgets('a tier with no art draws nothing, but keeps its space', (
    tester,
  ) async {
    await pump(tester, kRankLadder.first.assetPath); // Rookie

    expect(find.byType(Image), findsNothing);
    expect(tester.getSize(find.byType(RankBadge)), const Size(36, 36));
  });

  testWidgets('a file that cannot be loaded ends the same way', (tester) async {
    await pump(tester, 'assets/ranks/not_a_badge.webp');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(RankBadge)), const Size(36, 36));
  });

  testWidgets('a bundled badge is shown', (tester) async {
    await pump(tester, 'assets/ranks/gold.webp');

    expect(find.byType(Image), findsOneWidget);
  });
}
