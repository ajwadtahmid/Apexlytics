import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/widgets/error_card.dart';

void main() {
  Widget card({VoidCallback? onAction}) => ErrorCard(
    fullScreen: true,
    title: 'Ready to record',
    message: 'Apexlytics can record your ranked games as you play.',
    actionLabel: 'Start recording',
    onAction: onAction,
    onRetry: () {},
    onLearnMore: () {},
  );

  testWidgets('full-screen card scrolls on a short screen, so every button '
      'can still be tapped', (tester) async {
    tester.view.physicalSize = const Size(360, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var started = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(body: card(onAction: () => started++)),
        ),
      ),
    );

    // Taller than the screen, yet no overflow error.
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.ensureVisible(find.text('Start recording'));
    await tester.tap(find.text('Start recording'));
    expect(started, 1);
  });

  testWidgets('full-screen card still lays out when its parent has no bounded '
      'height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(children: [card(onAction: () {})]),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Start recording'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}
