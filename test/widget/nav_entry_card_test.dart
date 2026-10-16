import 'package:apexlytics/screens/ranked/ranked_sessions_list_screen.dart';
import 'package:apexlytics/widgets/nav_entry_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('shows its title and icon and reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        NavEntryCard(
          icon: Icons.timeline,
          title: 'Sessions',
          onTap: () => taps++,
        ),
      ),
    );

    expect(find.text('Sessions'), findsOneWidget);
    expect(find.byIcon(Icons.timeline), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.text('Sessions'));
    expect(taps, 1);
  });

  testWidgets('the Sessions entry hides itself when there are none', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(RankedSessionsEntry(sessions: const [], onRefresh: () async {})),
    );

    expect(find.text('Sessions'), findsNothing);
  });
}
