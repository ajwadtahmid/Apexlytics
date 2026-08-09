import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/widgets/player_info_card.dart';

import '../helpers.dart';

void main() {
  Future<void> pump(WidgetTester tester, int? rpDelta) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlayerInfoCard(
          stats: buildStats(uid: 'uid123', rankScore: 6758),
          rpDelta: rpDelta,
        ),
      ),
    ),
  );

  testWidgets('renders a zero delta in the same format as any other', (
    tester,
  ) async {
    await pump(tester, 0);
    expect(find.text('+0 RP this week'), findsOneWidget);
  });

  testWidgets('renders a positive delta', (tester) async {
    await pump(tester, 2820);
    expect(find.text('+2,820 RP this week'), findsOneWidget);
  });

  testWidgets('renders a negative delta', (tester) async {
    await pump(tester, -1500);
    expect(find.text('-1,500 RP this week'), findsOneWidget);
  });

  testWidgets('hides the badge only when there is no data at all', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.textContaining('RP this week'), findsNothing);
  });
}
