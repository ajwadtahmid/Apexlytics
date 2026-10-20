import 'dart:io' show File, Platform;
import 'dart:typed_data' show ByteData;

import 'package:apexlytics/screens/ranked/widgets/ranked_highlight_cards.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/widgets/rp_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets('every legend card puts its RP pill at the same right edge, '
      'whatever the pill reads', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Different RP per game, so the pills have different widths.
    final legends = [
      for (final (name, rp) in [
        ('Axle', 5),
        ('Wraith', 144),
        ('Bangalore', 256),
        ('Octane', -30),
      ])
        (RankedAgg()..addAll([
              for (var i = 0; i < 4; i++)
                buildMatch(
                  legend: name,
                  rp: rp,
                  start: 1782090000 + i * 5000 + rp,
                ),
            ]))
            .toLegend(name),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RankedOverviewHighlights(
              legends: legends,
              maps: const [],
              legendMatchesFor: (_) async => const [],
              mapMatchesFor: (_) async => const [],
              onRefresh: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final pills = find.byType(RpPill);
    expect(pills, findsNWidgets(4));
    final rights = {
      for (var i = 0; i < 4; i++) tester.getTopRight(pills.at(i)).dx,
    };
    expect(rights, hasLength(1), reason: 'pill right edges: $rights');
  });
  group('on a 393 dp phone', () {
    // The default test font is far wider than any real one, so the SDK's
    // Roboto is loaded for a true measure.
    setUpAll(() async {
      final root = Platform.environment['FLUTTER_ROOT'];
      if (root == null) return;
      final loader = FontLoader('Roboto');
      for (final file in [
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-Bold.ttf',
      ]) {
        final f = File('$root/bin/cache/artifacts/material_fonts/$file');
        if (f.existsSync()) {
          loader.addFont(
            Future.value(ByteData.view(f.readAsBytesSync().buffer)),
          );
        }
      }
      await loader.load();
    });

    testWidgets('a legend card shows its stats at full size, not shrunk to '
        'fit beside the pill', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // The widest figures a card is likely to carry.
      final legends = [
        for (final (name, rp, kills, damage, games) in [
          ('Wraith', -40, 1, 349, 5),
          ('Bangalore', 123, 12, 1234, 108),
        ])
          (RankedAgg()..addAll([
                for (var i = 0; i < games; i++)
                  buildMatch(
                    legend: name,
                    rp: rp,
                    kills: kills,
                    damage: damage,
                    start: 1782090000 + i * 5000,
                  ),
              ]))
              .toLegend(name),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RankedOverviewHighlights(
                legends: legends,
                maps: const [],
                legendMatchesFor: (_) async => const [],
                mapMatchesFor: (_) async => const [],
                onRefresh: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final labels = find.text('TOTAL RP');
      expect(labels, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        // A FittedBox that shrinks its child draws it smaller than it lays it
        // out: the drawn width is the laid-out width times the scale.
        final scale =
            tester.getRect(labels.at(i)).width /
            tester.getSize(labels.at(i)).width;
        expect(scale, closeTo(1, 0.001), reason: 'card $i is drawn at $scale');
      }
    });
  });
}
