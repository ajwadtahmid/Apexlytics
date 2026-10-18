import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/utils/lookup_form_state.dart';
import 'package:apexlytics/widgets/lookup_card.dart';

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    Widget child, {
    required Size size,
    required double textScale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  group('LookupCard', () {
    for (final (width, scale) in [(320.0, 1.3), (320.0, 2.0), (360.0, 1.5)]) {
      for (final byUid in [false, true]) {
        testWidgets('fits at ${width.toInt()} dp with text ×$scale, '
            '${byUid ? 'by UID' : 'by name'}', (tester) async {
          final state = LookupFormState(
            name: 'Aceu',
            uid: '1001',
            platform: byUid ? 'SWITCH' : 'PC',
          );
          addTearDown(state.dispose);
          await pumpAt(
            tester,
            LookupCard(
              state: state,
              onSubmit: () {},
              arrowSubmits: true,
              error: 'Player not found. Check the name and platform.',
            ),
            size: Size(width, 640),
            textScale: scale,
          );

          expect(tester.takeException(), isNull);
          for (final label in ['PC', 'PS', 'Xbox', 'Switch']) {
            expect(find.text(label), findsOneWidget, reason: label);
          }
          expect(
            find.text('Find your UID'),
            byUid ? findsOneWidget : findsNothing,
          );
        });
      }
    }
  });

  group('AppTheme.scaledWithText', () {
    Future<double> scaled(WidgetTester tester, double textScale) async {
      late double result;
      await pumpAt(
        tester,
        Builder(
          builder: (context) {
            result = AppTheme.scaledWithText(context, 80);
            return const SizedBox();
          },
        ),
        size: const Size(360, 640),
        textScale: textScale,
      );
      return result;
    }

    testWidgets('is the base height at normal and smaller text', (
      tester,
    ) async {
      expect(await scaled(tester, 1.0), 80);
      expect(await scaled(tester, 0.8), 80);
    });

    testWidgets('grows with larger text', (tester) async {
      expect(await scaled(tester, 1.5), closeTo(120, 0.001));
      expect(await scaled(tester, 2.0), closeTo(160, 0.001));
    });
  });
}
