import 'dart:convert';

import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/screens/ranked/ranked_compare_tab.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/ranked/ranked_period.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final season = SeasonMeta(
    id: 's29_s1',
    displayName: 'S29 Split 1',
    start: DateTime.now().subtract(const Duration(days: 10)),
    end: DateTime.now().add(const Duration(days: 30)),
  );
  final splits = [
    RankedSplitBucket(
      id: season.id,
      displayName: season.displayName,
      season: season,
    ),
  ];

  LegendBreakdown pick(String legend, int games) => LegendBreakdown(
    legend: legend,
    games: games,
    totalRp: 0,
    totalKills: 0,
    totalDamage: 0,
    killsGames: 0,
    damageGames: 0,
    totalLengthSecs: 0,
    wins: 0,
    losses: 0,
  );

  RankedSplitDetail detail(
    int games,
    int netRp, [
    List<LegendBreakdown> legends = const [],
  ]) => (
    summary: RankedSummary(
      games: games,
      netRp: netRp,
      currentRp: 1000,
      latestRankImg: '',
      totalKills: games,
      totalDamage: games * 500,
      killsGames: games,
      damageGames: games,
      totalLengthSecs: games * 600,
      wins: games ~/ 4,
      losses: games - games ~/ 4,
    ),
    legends: legends,
    maps: const [],
    legendMap: const [],
    timeOfDay: const [],
    dayOfWeek: const [],
  );

  Future<List<String>> pump(
    WidgetTester tester,
    List<(String, String)> saved, {
    List<RankedSplitBucket>? altSplits,
    bool twoSplits = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'player_profiles': jsonEncode([
        for (final (name, uid) in saved)
          {'name': name, 'uid': uid, 'platform': 'PC'},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final mine = twoSplits
        ? [
            ...splits,
            RankedSplitBucket(
              id: 's28_s2',
              displayName: 'S28 Split 2',
              season: season,
            ),
          ]
        : splits;
    final asked = <String>[];
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          rankedSplitsProvider.overrideWith(
            (ref, uid) async => uid == '1' ? mine : altSplits ?? splits,
          ),
          rankedSplitDetailProvider.overrideWith((ref, arg) async {
            asked.add(arg.uid);
            if (arg.uid != '1') return detail(20, 100, [pick('Wraith', 20)]);
            // Two splits of yours differ in what you played.
            return detail(
              40,
              300,
              arg.splitId == 's28_s2'
                  ? [pick('Octane', 40)]
                  : [pick('Wraith', 40)],
            );
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RankedCompareTab(uid: '1', splits: mine),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return asked;
  }

  testWidgets('with a single profile and one split, it is as it always was', (
    tester,
  ) async {
    await pump(tester, [('Main', '1')]);
    expect(find.textContaining('Need at least two splits'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('with a single profile and two splits, the labels stay plain', (
    tester,
  ) async {
    await pump(tester, [('Main', '1')], twoSplits: true);
    expect(find.text('COMPARING'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('a profile with no UID yet is not offered', (tester) async {
    await pump(tester, [('Main', '1'), ('Pending', '')]);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('each side names its profile, both starting on yours', (
    tester,
  ) async {
    await pump(tester, [('Main', '1'), ('Alt', '2')]);

    expect(find.text('COMPARING · MAIN'), findsOneWidget);
    expect(find.text('CURRENT · MAIN'), findsOneWidget);
  });

  testWidgets('switching one side to another profile compares the two', (
    tester,
  ) async {
    final asked = await pump(tester, [('Main', '1'), ('Alt', '2')]);

    await tester.tap(find.text('COMPARING · MAIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alt'));
    await tester.pumpAndSettle();

    expect(find.text('COMPARING · ALT'), findsOneWidget);
    expect(find.text('CURRENT · MAIN'), findsOneWidget);
    expect(asked, contains('2'));
    // Names carry the profile once the sides differ.
    expect(find.text('Alt · S29 Split 1'), findsWidgets);
    expect(find.text('Main · S29 Split 1'), findsWidgets);
    expect(find.text('+200'), findsOneWidget); // net RP, 300 against 100
  });

  testWidgets('one split is enough to compare two profiles', (tester) async {
    await pump(tester, [('Main', '1'), ('Alt', '2')]);
    // Same profile on both sides, one split: nothing to compare yet.
    expect(find.textContaining('Need at least two splits'), findsOneWidget);

    await tester.tap(find.text('COMPARING · MAIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Need at least two splits'), findsNothing);
  });

  testWidgets('says so when the other profile has no games', (tester) async {
    await pump(tester, [('Main', '1'), ('Alt', '2')], altSplits: const []);

    await tester.tap(find.text('COMPARING · MAIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alt'));
    await tester.pumpAndSettle();

    expect(find.text('No recorded games'), findsOneWidget);
  });

  testWidgets('the Current side is locked to your profile', (tester) async {
    await pump(tester, [('Main', '1'), ('Alt', '2')]);

    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.text('CURRENT · MAIN'), findsOneWidget);
  });

  testWidgets('another profile starts on the split you are looking at', (
    tester,
  ) async {
    await pump(tester, [('Main', '1'), ('Alt', '2')], twoSplits: true);
    // Same profile: the previous split against the current one.
    expect(find.text('S28 Split 2'), findsWidgets);

    await tester.tap(find.text('COMPARING · MAIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alt'));
    await tester.pumpAndSettle();

    expect(find.text('S28 Split 2'), findsNothing);
    expect(find.text('Alt · S29 Split 1'), findsWidgets);
    expect(find.text('Main · S29 Split 1'), findsWidgets);
  });

  testWidgets('what changed shows for splits, not for two profiles', (
    tester,
  ) async {
    await pump(tester, [('Main', '1'), ('Alt', '2')], twoSplits: true);
    expect(find.text('What changed'), findsOneWidget);

    await tester.tap(find.text('COMPARING · MAIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alt'));
    await tester.pumpAndSettle();

    expect(find.text('What changed'), findsNothing);

    // Back to yourself, and it returns.
    await tester.tap(find.text('COMPARING · ALT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main').last);
    await tester.pumpAndSettle();
    expect(find.text('What changed'), findsOneWidget);
  });
}
