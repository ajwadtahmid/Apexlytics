import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/screens/ranked/widgets/history_filter.dart';
import 'package:apexlytics/screens/ranked/widgets/match_history_items.dart';
import 'package:apexlytics/screens/ranked/widgets/match_history_list.dart';

void main() {
  // Noon local time today, so a game never lands on the wrong side of
  // midnight and the newest day is "Today".
  final now = DateTime.now();
  final base =
      DateTime(now.year, now.month, now.day, 12).millisecondsSinceEpoch ~/ 1000;

  RankedMatch game({
    required int dayOffset,
    required int slot,
    String legend = 'Axle',
    String map = 'olympus_rotation',
    int rp = 10,
    int? kills = 2,
    int? damage = 500,
    bool excluded = false,
    int length = 600,
  }) {
    final start = base - dayOffset * 86400 + slot * 1000;
    final m = RankedMatch.fromJson({
      'uid': '1',
      'name': 'Tester',
      'legendPlayed': legend,
      'gameMode': 'BATTLE_ROYALE',
      'gameLengthSecs': length,
      'gameStartTimestamp': start,
      'gameEndTimestamp': start + length,
      'gameData': [
        if (kills != null) {'key': 'kills', 'value': kills, 'name': 'BR Kills'},
        if (damage != null)
          {'key': 'damage', 'value': damage, 'name': 'BR Damage'},
      ],
      'BRScoreChange': rp,
      'BRScore': 1000,
      'map': map,
      'isPartyFull': false,
    });
    return excluded ? m.withExcluded(true) : m;
  }

  group('day header summary', () {
    test('rolls up record, average RP, kills, damage and time', () {
      final day = [
        game(dayOffset: 0, slot: 3, rp: 20, kills: 4, damage: 900),
        game(dayOffset: 0, slot: 2, rp: -10, kills: 1, damage: 300),
        game(dayOffset: 0, slot: 1, rp: 30, kills: 3, damage: 800),
      ];
      final h = buildDayItems(day).whereType<DayHeaderItem>().single;
      expect(h.wins, 2);
      expect(h.losses, 1);
      expect(h.avgRp, closeTo(40 / 3, 0.001));
      expect(h.kills, 8);
      expect(h.damage, 2000);
      expect(h.avgDamage, closeTo(2000 / 3, 0.001));
      expect(h.playSecs, 1800);
    });

    test('skips excluded games and has no average without ranked games', () {
      final day = [
        game(dayOffset: 0, slot: 2, rp: 20, kills: 5, excluded: true),
        game(dayOffset: 0, slot: 1, rp: 0, kills: 2, damage: 100),
      ];
      final h = buildDayItems(day).whereType<DayHeaderItem>().single;
      expect(h.kills, 2);
      expect(h.wins, 0);
      expect(h.avgRp, isNull);
    });
  });

  group('HistoryFilter', () {
    final pool = [
      game(dayOffset: 0, slot: 4, rp: 20),
      game(dayOffset: 0, slot: 3, rp: -10, legend: 'Wraith'),
      game(dayOffset: 0, slot: 2, rp: 0), // pubs
      game(dayOffset: 0, slot: 1, rp: 15, map: 'kings_canyon'),
    ];

    test('defaults to ranked games only', () {
      const f = HistoryFilter();
      expect(f.activeCount, 0);
      expect(f.apply(pool), hasLength(3));
    });

    test('combines mode, result, legend and map', () {
      expect(
        const HistoryFilter(mode: HistoryMode.casual).apply(pool),
        hasLength(1),
      );
      expect(
        const HistoryFilter(result: HistoryResult.losses).apply(pool),
        hasLength(1),
      );
      final f = const HistoryFilter().copyWith(
        legends: {'Axle'},
        mapKeys: {'kings_canyon'},
      );
      expect(f.apply(pool), hasLength(1));
      expect(f.activeCount, 2);
    });
  });

  group('MatchHistoryList', () {
    // Eleven days of games, so the pinned headers have something to pin to.
    final matches = [
      for (var d = 0; d < 11; d++)
        for (var s = 0; s < 3; s++) game(dayOffset: d, slot: 3 - s, kills: s),
    ];

    Future<void> pump(WidgetTester tester, ProviderContainer? c) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c ?? ProviderContainer(),
          child: MaterialApp(
            home: Scaffold(
              body: MatchHistoryList(
                matches: matches,
                onRefresh: () async {},
                averagePool: matches,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('collapsing a day hides its matches and keeps its header', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pump(tester, container);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Axle'), findsWidgets);
      final rowsBefore = find.text('Axle').evaluate().length;

      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Axle').evaluate().length, lessThan(rowsBefore));

      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(find.text('Axle').evaluate().length, rowsBefore);
    });

    testWidgets('scrolls with pinned headers without errors', (tester) async {
      await pump(tester, null);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail sheet steps through matches', (tester) async {
      await pump(tester, null);
      await tester.tap(find.text('Axle').first);
      await tester.pumpAndSettle();
      expect(find.text('1 of 33'), findsOneWidget);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 33'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous match'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 33'), findsOneWidget);
    });
  });
}
