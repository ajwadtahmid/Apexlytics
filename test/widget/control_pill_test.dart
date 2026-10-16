import 'package:apexlytics/widgets/control_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget pill) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: pill))),
  );

  testWidgets('shows the prefix, icon and label, and taps through', (
    tester,
  ) async {
    var taps = 0;
    await pump(
      tester,
      ControlPill(
        prefix: 'Sort:',
        icon: Icons.bolt,
        label: 'Damage',
        onTap: () => taps++,
      ),
    );

    expect(find.text('Sort:'), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
    await tester.tap(find.text('Damage'));
    expect(taps, 1);
  });

  testWidgets('without a prefix it is just the pill', (tester) async {
    await pump(
      tester,
      ControlPill(icon: Icons.flag, label: 'Set goal', onTap: () {}),
    );

    expect(find.text('Set goal'), findsOneWidget);
    expect(find.text('Sort:'), findsNothing);
  });
}
