import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/sheet_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('draws the handle at the size the theme defines', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          bottomSheetTheme: const BottomSheetThemeData(
            dragHandleSize: Size(50, 6),
            dragHandleColor: Colors.red,
          ),
        ),
        home: const Scaffold(body: SheetHandle()),
      ),
    );

    expect(tester.getSize(find.byType(Container)), const Size(50, 6));
    final box = tester.widget<Container>(find.byType(Container));
    expect((box.decoration as BoxDecoration).color, Colors.red);
  });

  testWidgets('matches the app theme handle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.materialTheme,
        home: const Scaffold(body: SheetHandle()),
      ),
    );

    expect(tester.getSize(find.byType(Container)), const Size(36, 4));
  });
}
