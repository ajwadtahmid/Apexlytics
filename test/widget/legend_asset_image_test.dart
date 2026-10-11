import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/widgets/legend_asset_image.dart';

void main() {
  Future<void> pump(WidgetTester tester, String imageKey) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 80,
            height: 90,
            child: LegendAssetImage(imageKey: imageKey, displayName: 'Zed'),
          ),
        ),
      ),
    );
    // Let the asset loads (and the failed one) resolve.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  testWidgets('a known legend shows its own portrait, not a fallback', (
    tester,
  ) async {
    await pump(tester, 'wraith');

    expect(find.text('Z'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a legend with no portrait falls back to the career art, and '
      'only then to a letter', (tester) async {
    await pump(tester, 'not_a_legend');

    // career.webp exists, so it is what shows and the letter tile is never
    // reached.
    expect(
      find.byWidgetPredicate((w) {
        if (w is! Image) return false;
        final provider = w.image;
        final inner = provider is ResizeImage
            ? provider.imageProvider
            : provider;
        return inner is AssetImage && inner.assetName.endsWith('career.webp');
      }),
      findsOneWidget,
    );
    expect(find.text('Z'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
