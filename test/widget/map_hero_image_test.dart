import 'package:apexlytics/constants/map_constants.dart';
import 'package:apexlytics/screens/home/widgets/map_hero_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, String map, String url) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MapHeroImage(mapName: map, assetUrl: url)),
        ),
      );

  const apiUrl = 'https://api.apexlegendsstatus.com/assets/maps/whatever.png';

  testWidgets('every Battle Royale map uses its bundled image, not the API URL', (
    tester,
  ) async {
    for (final info in kBattleRoyaleMaps.values) {
      await pump(tester, info.name, apiUrl);

      expect(find.byType(CachedNetworkImage), findsNothing, reason: info.name);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).imageProvider, isA<AssetImage>());
      expect(
        ((image.image as ResizeImage).imageProvider as AssetImage).assetName,
        info.asset,
        reason: info.name,
      );
    }
  });

  testWidgets('a map with no bundled image (Mixtape) uses the API image', (
    tester,
  ) async {
    await pump(tester, 'Overflow', apiUrl);

    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(
      tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage)).imageUrl,
      apiUrl,
    );
  });

  testWidgets('no bundled image and no API URL shows the plain placeholder', (
    tester,
  ) async {
    await pump(tester, 'Overflow', '');

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
  });
}
