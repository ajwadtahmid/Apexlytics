import 'package:apexlytics/widgets/info_sheet.dart';
import 'package:apexlytics/widgets/sheet_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester t, {
    required List<String> lines,
    double textScale = 1,
  }) async {
    t.view.physicalSize = const Size(400, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showInfoSheet(context, title: 'How to read', lines: lines),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('shows a handle, the title and each line', (t) async {
    await open(t, lines: ['First point.', 'Second point.']);

    expect(find.byType(SheetHandle), findsOneWidget);
    expect(find.text('How to read'), findsOneWidget);
    expect(find.text('First point.'), findsOneWidget);
    expect(find.text('Second point.'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('How to read')).dy,
      lessThan(t.getTopLeft(find.text('First point.')).dy),
    );
    expect(
      t.getTopLeft(find.text('First point.')).dy,
      lessThan(t.getTopLeft(find.text('Second point.')).dy),
    );
  });

  testWidgets('scrolls, rather than overflowing, when the text is long', (
    t,
  ) async {
    await open(
      t,
      lines: [for (var i = 0; i < 12; i++) 'Point $i. ${'More words. ' * 20}'],
      textScale: 2,
    );

    expect(t.takeException(), isNull);
    final scroll = find.byType(SingleChildScrollView);
    expect(scroll, findsOneWidget);

    await t.drag(scroll, const Offset(0, -2000));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.textContaining('Point 11.'), findsOneWidget);
  });
}
