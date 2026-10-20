import 'dart:io';
import 'dart:typed_data';

import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/models/server_status.dart';
import 'package:apexlytics/providers/proxy_health_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/home/server_status_page.dart';
import 'package:apexlytics/services/proxy_health.dart';
import 'package:apexlytics/screens/ranked/ranked_compare_tab.dart';
import 'package:apexlytics/screens/ranked/ranked_personal_records_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_recap_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_recap_share_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_pick_rate_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_session_detail_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_time_breakdown_screen.dart';
import 'package:apexlytics/screens/ranked/ranked_sessions_screen.dart';
import 'package:apexlytics/screens/ranked/widgets/sessions_overview.dart';
import 'package:apexlytics/screens/ranked/ranked_share_screens.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_share_cards.dart';
import 'package:apexlytics/utils/ranked/split_recap.dart';
import 'package:apexlytics/widgets/share_card.dart';
import 'package:apexlytics/screens/ranked/widgets/history_filter.dart';
import 'package:apexlytics/screens/ranked/widgets/match_history_list.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_entity_compare.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_best_legend_per_map.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_highlight_cards.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_rp_chart.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_slot_chart.dart';
import 'package:apexlytics/screens/ranked/widgets/split_changes_card.dart';
import 'package:apexlytics/utils/formatting/snapshot_types.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/widgets/graph_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          await prefsOverride(),
          // Nothing leaves the test.
          proxyCheckerProvider.overrideWithValue(
            (_) async => (state: ProxyState.online, latency: Duration.zero),
          ),
          ...overrides,
        ],
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

  testWidgets('the Personal Records page', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 800,
        child: RankedPersonalRecordsScreen(
          onRefresh: () async {},
          stats: buildStats(),
          matches: [
            for (var i = 0; i < 4; i++)
              buildMatch(
                legend: 'Mad Maggie',
                start: 1782090000 + i * 1500,
                kills: 3,
                damage: 1200,
              ),
          ],
          sessions: sessionize([
            for (var i = 0; i < 4; i++)
              buildMatch(
                legend: 'Mad Maggie',
                start: 1782090000 + i * 1500,
                kills: 3,
                damage: 1200,
              ),
          ]),
        ),
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the Recap page', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 800,
        child: RankedRecapScreen(
          matches: [
            for (var i = 0; i < 4; i++)
              buildMatch(
                legend: 'Mad Maggie',
                start: 1782090000 + i * 1500,
                rp: 20,
                kills: 3,
                damage: 1200,
              ),
          ],
          scope: 'S30 Split 2',
          playerName: 'A Rather Long Player Name',
        ),
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the Recap card page', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 800,
        child: RankedRecapShareScreen(
          recap: splitRecap([
            for (var i = 0; i < 4; i++)
              buildMatch(
                legend: 'Mad Maggie',
                start: 1782090000 + i * 1500,
                rp: 20,
                kills: 3,
                damage: 1200,
              ),
          ]),
          scope: 'S30 Split 2',
          playerName: 'A Rather Long Player Name',
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

  testWidgets('the best legend per map rows', (tester) async {
    final cells = legendMapBreakdowns([
      for (var i = 0; i < 5; i++)
        buildMatch(legend: 'Mad Maggie', map: 'storm_point_rotation', rp: 40),
    ]);
    await pump(
      tester,
      RankedBestLegendPerMap(cells: cells, currentMapName: 'Storm Point'),
    );
    expectNoOverflow();
  });

  testWidgets('the History selection bar', (tester) async {
    final games = [buildMatch(), buildMatch(start: 1782091000)];
    await pump(
      tester,
      SizedBox(
        height: 700,
        child: MatchHistoryList(
          matches: games,
          onRefresh: () async {},
          selectable: true,
        ),
      ),
    );
    await tester.longPress(find.text('Axle').first);
    await tester.pump();

    expect(find.text('1 selected'), findsOneWidget);
    expectNoOverflow();
  });

  testWidgets('the History filter sheet', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showHistoryFilterSheet(
            context,
            filter: const HistoryFilter(),
            pool: [buildMatch()],
            onChanged: (_) {},
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expectNoOverflow();
  });

  testWidgets('the legend comparison table', (tester) async {
    await pump(
      tester,
      RankedEntityCompare(
        kind: CompareKind.legends,
        matches: [
          for (var i = 0; i < 4; i++)
            buildMatch(
              legend: 'Mad Maggie',
              start: 1782090000 + i * 5000,
              kills: 2,
              damage: 900,
            ),
          for (var i = 0; i < 4; i++)
            buildMatch(
              legend: 'Newcastle',
              rp: -12,
              start: 1782190000 + i * 5000,
              kills: 1,
              damage: 300,
            ),
        ],
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the hour and day comparison charts', (tester) async {
    const a = [(slot: 9, games: 5, netRp: 40), (slot: 21, games: 4, netRp: -8)];
    const b = [(slot: 21, games: 6, netRp: 30), (slot: 23, games: 3, netRp: 9)];
    await pump(
      tester,
      Column(
        children: [
          RankedSlotChart.hours(
            nameA: 'Season 28 Split 1',
            nameB: 'Season 28 Split 2',
            a: a,
            b: b,
          ),
          RankedSlotChart.days(
            nameA: 'Season 28 Split 1',
            nameB: 'Season 28 Split 2',
            a: const [(slot: 2, games: 5, netRp: 40)],
            b: const [(slot: 6, games: 6, netRp: -30)],
          ),
        ],
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the what-changed card', (tester) async {
    List<RankedMatch> played(String legend, String map, int n, int rp) => [
      for (var i = 0; i < n; i++)
        buildMatch(
          legend: legend,
          map: map,
          rp: rp,
          start: 1782090000 + i * 5000,
        ),
    ];
    final before = [
      ...played('Mad Maggie', 'olympus_rotation', 6, 20),
      ...played('Newcastle', 'olympus_rotation', 4, 5),
    ];
    final after = [
      ...played('Mad Maggie', 'olympus_rotation', 2, -10),
      ...played('Newcastle', 'olympus_rotation', 8, -10),
    ];
    await pump(
      tester,
      SplitChangesCard(
        legendsA: legendBreakdowns(before),
        legendsB: legendBreakdowns(after),
        mapsA: mapBreakdowns(before),
        mapsB: mapBreakdowns(after),
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the Pick Rate screen', (tester) async {
    List<RankedMatch> played(String legend, int n, int rp) => [
      for (var i = 0; i < n; i++)
        buildMatch(legend: legend, rp: rp, start: 1782090000 + i * 5000),
    ];
    final all = [
      ...played('Mad Maggie', 8, -5),
      ...played('Newcastle', 4, 20),
      ...played('Bangalore', 4, -3),
    ];
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: app!,
          ),
          home: RankedPickRateScreen(
            summary: summarize(all),
            legends: legendBreakdowns(all),
          ),
        ),
      ),
    );
    await tester.pump();
    expectNoOverflow();

    await tester.tap(find.byTooltip('Customize'));
    await tester.pumpAndSettle();
    expectNoOverflow();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Table'));
    await tester.pump();
    expectNoOverflow();
  });

  testWidgets('the Sessions overview and a session tile', (tester) async {
    final played = sessionize([
      for (var s = 0; s < 3; s++)
        for (var g = 0; g < 4; g++)
          buildMatch(
            rp: g.isEven ? 25 : -12,
            start: 1782000000 + s * 6 * 3600 + g * 1500,
          ),
    ]);
    await pump(
      tester,
      Column(
        children: [
          SessionsOverview(sessions: played, onOpen: (_) {}),
          SessionRecapTile(
            session: played.first,
            badge: SessionBadge.best,
            onTap: () {},
          ),
        ],
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the session detail page', (tester) async {
    final played = sessionize([
      for (var g = 0; g < 6; g++)
        buildMatch(
          legend: g.isEven ? 'Mad Maggie' : 'Newcastle',
          rp: g.isEven ? 25 : -12,
          kills: g,
          damage: 300 * g,
          start: 1782000000 + g * 2400,
        ),
    ]).single;
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: app!,
        ),
        home: RankedSessionDetailScreen(
          session: played,
          onRefresh: () async {},
        ),
      ),
    );
    await tester.pump();
    expectNoOverflow();
  });

  testWidgets('the Performance Trends page', (tester) async {
    final played = sessionize([
      for (var s = 0; s < 12; s++)
        for (var g = 0; g < 3; g++)
          buildMatch(
            rp: s < 6 ? -15 : 25,
            start: 1782000000 + s * 6 * 3600 + g * 1500,
          ),
    ]);
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: app!,
          ),
          home: RankedTimeBreakdownScreen(
            hourBuckets: const [
              HourBucket(hourLocal: 19, games: 14, netRp: 120),
              HourBucket(hourLocal: 9, games: 12, netRp: -48),
            ],
            weekdayBuckets: const [
              WeekdayBucket(weekday: 6, games: 14, netRp: 120),
              WeekdayBucket(weekday: 1, games: 12, netRp: -48),
            ],
            sessions: played,
          ),
        ),
      ),
    );
    await tester.pump();
    expectNoOverflow();
  });

  testWidgets('the Comparison switch', (tester) async {
    await pump(
      tester,
      const RankedCompareTab(uid: '1', splits: [], matches: []),
    );
    expectNoOverflow();
  });

  testWidgets('the Recap and Personal Records entries side by side', (
    tester,
  ) async {
    final games = [
      for (var i = 0; i < 4; i++) buildMatch(start: 1782090000 + i * 1500),
    ];
    await pump(
      tester,
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RankedRecapEntry(
                matches: games,
                scope: 'S30 Split 2',
                playerName: 'Reptar',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RankedPersonalRecordsEntry(
                stats: buildStats(),
                matches: games,
                sessions: const [],
                onRefresh: () async {},
              ),
            ),
          ],
        ),
      ),
    );
    expectNoOverflow();
  });

  testWidgets('the share screen and its card', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 900,
        child: ShareCardScreen(
          title: 'Recap',
          cardBuilder: (show) => RecapShareCard(
            recap: splitRecap([
              for (var i = 0; i < 4; i++)
                buildMatch(
                  legend: 'Mad Maggie',
                  start: 1782090000 + i * 1500,
                  cumulativeRp: 1020 + i * 20,
                ),
            ]),
            scope: 'S30 Split 2 Week 12',
            playerName: show ? 'AReallyLongPlayerNameHere' : null,
          ),
        ),
      ),
    );
    expectNoOverflow();
  });
}
