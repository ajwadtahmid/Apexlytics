import 'dart:io';
import 'dart:typed_data';

import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/models/server_status.dart';
import 'package:apexlytics/screens/home/server_status_page.dart';
import 'package:apexlytics/screens/ranked/ranked_personal_records_screen.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_highlight_cards.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_rp_chart.dart';
import 'package:apexlytics/utils/formatting/snapshot_types.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/widgets/graph_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A 320 dp phone at the largest text size Android offers. Loads the SDK's
/// Roboto, since the default test font is far wider than any real one.
void main() {
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
        loader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      }
    }
    await loader.load();
  });

  final errors = <String>[];

  setUp(() {
    errors.clear();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exceptionAsString());
    addTearDown(() => FlutterError.onError = previous);
  });

  void expectNoOverflow() =>
      expect(errors.where((e) => e.contains('overflowed')), isEmpty);

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: app!,
          ),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  final matches = [
    for (var i = 0; i < 6; i++)
      buildMatch(start: 1782090000 + i * 900, kills: 2, damage: 500),
  ];

  testWidgets('the RP chart header', (tester) async {
    await pump(
      tester,
      RankedRpChart(
        matches: matches,
        sessions: sessionize(matches),
        onShowBackup: () {},
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the snapshot graph header', (tester) async {
    final now = DateTime.now();
    final started = now.subtract(const Duration(days: 10));
    final season = SeasonMeta.fromApi(
      id: 'br_ranked_s30_s1',
      startSeconds: started.millisecondsSinceEpoch ~/ 1000,
      endSeconds:
          now.add(const Duration(days: 40)).millisecondsSinceEpoch ~/ 1000,
    );
    await pump(
      tester,
      GraphCard(
        snapshots: [
          StatSnapshot(
            timestamp: started.add(const Duration(hours: 2)),
            rp: 8000,
            seasonId: season.id,
          ),
        ],
        currentSeason: season,
        allSeasons: {season.id: season},
        currentRp: 8100,
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the Personal Records streak card', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 800,
        child: RankedPersonalRecordsScreen(
          uid: '1',
          matches: matches,
          splits: const [],
        ),
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the server status card names', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 800,
        child: ServerStatusPage(
          status: ServerStatus.fromJson({
            'selfCoreTest': {
              'EU-West': {'Status': 'UP', 'ResponseTime': 20, 'HTTPCode': 200},
            },
          }),
        ),
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the Strongest and Weakest legend cards', (tester) async {
    final legends = [
      for (final name in ['Axle', 'Wraith', 'Bangalore', 'Octane'])
        (RankedAgg()..addAll([
              buildMatch(legend: name, rp: 40),
              buildMatch(legend: name, rp: -10, start: 1782091000),
            ]))
            .toLegend(name),
    ];
    await pump(
      tester,
      RankedOverviewHighlights(
        legends: legends,
        maps: const [],
        legendMatchesFor: (_) async => const [],
        mapMatchesFor: (_) async => const [],
        onRefresh: () async {},
      ),
    );
    expectNoOverflow();
  });
}
