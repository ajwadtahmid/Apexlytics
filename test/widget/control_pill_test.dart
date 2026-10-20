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

  testWidgets('a trailing widget sits after the label', (tester) async {
    await pump(
      tester,
      ControlPill(
        icon: Icons.bolt,
        label: 'Damage',
        trailing: const Icon(Icons.arrow_downward, size: 13),
        onTap: () {},
      ),
    );

    final icon = tester.getTopLeft(find.byIcon(Icons.bolt)).dx;
    final label = tester.getTopLeft(find.text('Damage')).dx;
    final arrow = tester.getTopLeft(find.byIcon(Icons.arrow_downward)).dx;
    expect(icon, lessThan(label));
    expect(label, lessThan(arrow));
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
