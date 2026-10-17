import 'package:apexlytics/screens/ranked/widgets/ranked_highlight_cards.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/widgets/rp_pill.dart';
import 'package:flutter/material.dart';
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
}
