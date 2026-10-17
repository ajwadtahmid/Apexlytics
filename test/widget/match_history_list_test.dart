import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart'
    show kSessionGap;
import 'package:apexlytics/screens/ranked/ranked_entity_history_screen.dart';
import 'package:apexlytics/screens/ranked/widgets/history_filter.dart';
import 'package:apexlytics/screens/ranked/widgets/match_tags.dart';
import 'package:apexlytics/screens/ranked/widgets/match_history_items.dart';
import 'package:apexlytics/screens/ranked/widgets/match_history_list.dart';
import '../helpers.dart';

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
    return buildMatch(
      start: start,
      legend: legend,
      map: map,
      rp: rp,
      kills: kills,
      damage: damage,
      length: length,
      excluded: excluded,
    );
  }

  group('grouping by map and legend', () {
    test('a hand-corrected map key joins the synced rotation key', () {
      // A synced match is stored as `olympus_rotation`; the edit sheet writes
      // the bare catalogue key.
      final items = buildGroupedItems([
        game(dayOffset: 0, slot: 1, map: 'olympus_rotation'),
        game(dayOffset: 0, slot: 2, map: 'olympus'),
        game(dayOffset: 0, slot: 3, map: 'olympus_rotation'),
      ], MatchGrouping.byMap);

      final headers = items.whereType<GroupHeaderItem>().toList();
      expect(headers, hasLength(1));
      expect(headers.single.name, 'Olympus');
      expect(headers.single.games, 3);
    });

    test('legend spellings that differ only by case share one section', () {
      final items = buildGroupedItems([
        game(dayOffset: 0, slot: 1, legend: 'Bloodhound'),
        game(dayOffset: 0, slot: 2, legend: 'bloodhound'),
      ], MatchGrouping.byLegend);

      final headers = items.whereType<GroupHeaderItem>().toList();
      expect(headers, hasLength(1));
      expect(headers.single.name, 'Bloodhound');
      expect(headers.single.games, 2);
    });

    test('a group\'s average RP counts ranked games that count, like a '
        'session header and the Legends and Maps tabs', () {
      // The excluded game adds nothing to the total, so it isn't in the average.
      final items = buildGroupedItems([
        game(dayOffset: 0, slot: 3, rp: 50),
        game(dayOffset: 0, slot: 2, rp: 30),
        game(dayOffset: 0, slot: 1, rp: -200, excluded: true),
      ], MatchGrouping.byMap);

      final header = items.whereType<GroupHeaderItem>().single;
      expect(header.games, 3);
      expect(header.netRp, 80);
      expect(header.avgRp, closeTo(40, 0.001)); // not 80 / 3
    });

    test('casual games do not dilute a group\'s average either', () {
      final items = buildGroupedItems([
        game(dayOffset: 0, slot: 2, rp: 20),
        game(dayOffset: 0, slot: 1, rp: 0), // pubs: no RP movement
      ], MatchGrouping.byMap);

      expect(
        items.whereType<GroupHeaderItem>().single.avgRp,
        closeTo(20, 0.001),
      );
    });

    test('a group with no counted ranked game has no average to show', () {
      final items = buildGroupedItems([
        game(dayOffset: 0, slot: 1, rp: 0),
        game(dayOffset: 0, slot: 2, rp: -200, excluded: true),
      ], MatchGrouping.byMap);

      expect(items.whereType<GroupHeaderItem>().single.avgRp, isNull);
    });
  });

  group('session header summary', () {
    test('rolls up record, average RP, kills, damage and time', () {
      final day = [
        game(dayOffset: 0, slot: 3, rp: 20, kills: 4, damage: 900),
        game(dayOffset: 0, slot: 2, rp: -10, kills: 1, damage: 300),
        game(dayOffset: 0, slot: 1, rp: 30, kills: 3, damage: 800),
      ];
      final h = buildSessionItems(day).whereType<SessionHeaderItem>().single;
      expect(h.wins, 2);
      expect(h.losses, 1);
      expect(h.avgRp, closeTo(40 / 3, 0.001));
      expect(h.kills, 8);
      expect(h.damage, 2000);
      expect(h.playSecs, 1800);
    });

    test('counts the games that reported kills and damage', () {
      final h = buildSessionItems([
        game(dayOffset: 0, slot: 3, kills: null, damage: null),
        game(dayOffset: 0, slot: 2, kills: 4, damage: null),
        game(dayOffset: 0, slot: 1, kills: 1, damage: 300),
      ]).whereType<SessionHeaderItem>().single;
      expect(h.killsGames, 2);
      expect(h.damageGames, 1);
      expect(h.kills, 5);
    });

    test('skips auto-excluded games like hand-excluded ones', () {
      final day = [
        game(dayOffset: 0, slot: 3, rp: -1500, kills: 9, damage: 9000),
        game(dayOffset: 0, slot: 2, rp: 20, kills: 2, damage: 400),
        game(dayOffset: 0, slot: 1, rp: -10, kills: 1, damage: 200),
      ];
      final h = buildSessionItems(day).whereType<SessionHeaderItem>().single;
      expect(h.games, 3, reason: 'still listed in the session');
      expect(h.kills, 3);
      expect(h.damage, 600);
      expect(h.wins, 1);
      expect(h.losses, 1);
      expect(h.netRp, 10);
      expect(h.avgRp, closeTo(5, 0.001));
    });

    test('skips excluded games and has no average without ranked games', () {
      final day = [
        game(dayOffset: 0, slot: 2, rp: 20, kills: 5, excluded: true),
        game(dayOffset: 0, slot: 1, rp: 0, kills: 2, damage: 100),
      ];
      final h = buildSessionItems(day).whereType<SessionHeaderItem>().single;
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

    test('an auto-excluded game is neither a win nor a loss', () {
      final reset = [game(dayOffset: 0, slot: 1, rp: -1500)];
      expect(
        const HistoryFilter(result: HistoryResult.wins).apply(reset),
        isEmpty,
      );
      expect(
        const HistoryFilter(result: HistoryResult.losses).apply(reset),
        isEmpty,
      );
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

    test('a map or legend matches however its games spell it', () {
      // Sync stores `olympus_rotation`; the edit sheet writes `olympus`.
      final synced = game(dayOffset: 0, slot: 1, map: 'olympus_rotation');
      final corrected = game(dayOffset: 0, slot: 2, map: 'olympus');
      final other = game(dayOffset: 0, slot: 3, map: 'kings_canyon');
      final f = const HistoryFilter(mapKeys: {'olympus'});
      expect(f.apply([synced, corrected, other]), [synced, corrected]);

      final proper = game(dayOffset: 0, slot: 1, legend: 'Axle');
      final lower = game(dayOffset: 0, slot: 2, legend: 'axle');
      final wraith = game(dayOffset: 0, slot: 3, legend: 'Wraith');
      final byLegend = const HistoryFilter(legends: {'Axle'});
      expect(byLegend.apply([proper, lower, wraith]), [proper, lower]);
    });

    test('a date range keeps whole local days, both ends included', () {
      final today = DateTime.now();
      DateTime day(int back) =>
          DateTime(today.year, today.month, today.day - back);
      final games = [
        game(dayOffset: 0, slot: 1),
        game(dayOffset: 1, slot: 1),
        game(dayOffset: 2, slot: 1),
        game(dayOffset: 5, slot: 1),
      ];
      final f = HistoryFilter(
        dates: DateTimeRange(start: day(2), end: day(1)),
      );

      expect(f.apply(games), [games[1], games[2]]);
      expect(f.activeCount, 1);
    });

    test('an RP range keeps ranked games inside it and drops casual ones', () {
      final games = [
        game(dayOffset: 0, slot: 5, rp: 50),
        game(dayOffset: 0, slot: 4, rp: 20),
        game(dayOffset: 0, slot: 3, rp: -10),
        game(dayOffset: 0, slot: 2, rp: 0), // casual
      ];
      const all = HistoryFilter(mode: HistoryMode.all);

      expect(all.copyWith(minRp: 20).apply(games), [games[0], games[1]]);
      expect(all.copyWith(maxRp: 0).apply(games), [games[2]]);
      expect(all.copyWith(minRp: -10, maxRp: 20).apply(games), [
        games[1],
        games[2],
      ]);
      expect(all.copyWith(minRp: 20).activeCount, 2);
    });

    test('clearRp drops both bounds before applying new ones', () {
      final f = const HistoryFilter().copyWith(minRp: 10, maxRp: 40);
      expect(f.copyWith(clearRp: true).hasRpRange, isFalse);
      final moved = f.copyWith(clearRp: true, minRp: 30);
      expect(moved.minRp, 30);
      expect(moved.maxRp, isNull);
    });

    testWidgets('the sheet shows the RP range and a date preset', (
      tester,
    ) async {
      var filter = const HistoryFilter();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showHistoryFilterSheet(
                  context,
                  filter: filter,
                  pool: [game(dayOffset: 0, slot: 1)],
                  onChanged: (f) => filter = f,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('DATE'), findsOneWidget);
      expect(find.text('RP CHANGE (RANKED GAMES)'), findsOneWidget);
      expect(find.text('Any'), findsWidgets);

      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();

      expect(filter.dates, isNotNull);
      expect(filter.dates!.end.difference(filter.dates!.start).inDays, 6);
      expect(filter.activeCount, 1);
    });

    testWidgets('the sheet offers one chip per map, not one per spelling', (
      tester,
    ) async {
      final pool = [
        game(dayOffset: 0, slot: 1, map: 'olympus_rotation'),
        game(dayOffset: 0, slot: 2, map: 'olympus'),
        game(dayOffset: 0, slot: 3, legend: 'axle', map: 'kings_canyon'),
      ];
      var filter = const HistoryFilter();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showHistoryFilterSheet(
                  context,
                  filter: filter,
                  pool: pool,
                  onChanged: (f) => filter = f,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Olympus'), findsOneWidget);
      // `axle` and `Axle` would otherwise be two legend chips.
      expect(find.text('Axle'), findsOneWidget);

      // Choosing it finds both games.
      await tester.ensureVisible(find.text('Olympus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Olympus'));
      await tester.pump();
      expect(filter.apply(pool), hasLength(2));
    });

    testWidgets('the Done button is on screen without scrolling, however many '
        'legends the player has used', (tester) async {
      // 25 legends on a phone: the button used to sit under all the chips.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pool = [
        for (var i = 0; i < 25; i++)
          game(dayOffset: 0, slot: i + 1, legend: 'Legend $i'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showHistoryFilterSheet(
                  context,
                  filter: const HistoryFilter(),
                  pool: pool,
                  onChanged: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      expect(tester.getRect(find.text('Done')).bottom, lessThanOrEqualTo(640));
      // The last legend is below the fold.
      expect(find.text('Legend 24').hitTestable(), findsNothing);

      // Tapping it closes the sheet.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsNothing);
    });
  });

  group('exclusion tags', () {
    test('an auto-excluded match is explained as such', () {
      final notes = matchTagNotes(game(dayOffset: 0, slot: 1, rp: -1500));
      expect(notes, hasLength(1));
      expect(notes.single.label, 'Excluded');
      expect(notes.single.text, contains('automatically'));
      expect(notes.single.text, contains('-1,500'));
    });

    test('a hand-excluded match reads as left out of every stat', () {
      final notes = matchTagNotes(game(dayOffset: 0, slot: 1, excluded: true));
      expect(notes.single.label, 'Excluded');
      expect(notes.single.text, contains('every stat'));
    });

    test('a normal match has no exclusion note', () {
      expect(matchTagNotes(game(dayOffset: 0, slot: 1)), isEmpty);
    });
  });

  group('sessions', () {
    int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

    RankedMatch at(DateTime start, {bool ranked = true, int length = 600}) =>
        buildMatch(start: secs(start), rp: ranked ? 10 : 0, length: length);

    // Newest first, as the list expects.
    List<RankedMatch> newestFirst(Iterable<RankedMatch> ms) =>
        ms.toList()..sort((a, b) => b.endTime.compareTo(a.endTime));

    List<SessionHeaderItem> headers(List<HistoryItem> items) =>
        items.whereType<SessionHeaderItem>().toList();

    test(
      'a session that crosses midnight is one entry with a divider inside',
      () {
        final day = DateTime(2025, 3, 10);
        final games = newestFirst([
          for (var i = 0; i < 10; i++)
            at(day.add(Duration(hours: 22, minutes: i * 12))),
          at(DateTime(2025, 3, 11, 0, 5)),
        ]);
        final items = buildSessionItems(games);

        expect(headers(items), hasLength(1));
        expect(headers(items).single.games, 11);
        final dividers = items.whereType<DayDividerItem>().toList();
        expect(dividers, hasLength(1));
        expect(dividers.single.later, DateTime(2025, 3, 11));
        expect(dividers.single.earlier, day);
        // Between the last game of the 10th and the first of the 11th.
        final i = items.indexOf(dividers.single);
        expect((items[i - 1] as MatchItem).match.startTime.toLocal().day, 11);
        expect((items[i + 1] as MatchItem).match.startTime.toLocal().day, 10);
        expect(headers(items).single.start.toLocal().day, 10);
      },
    );

    test('a gap over the session limit splits, one at the limit does not', () {
      final first = at(DateTime(2025, 3, 10, 10));
      final atLimit = at(first.endTime.toLocal().add(kSessionGap));
      final pastLimit = at(
        first.endTime.toLocal().add(kSessionGap + const Duration(seconds: 1)),
      );

      expect(
        headers(buildSessionItems(newestFirst([first, atLimit]))),
        hasLength(1),
      );

      final items = buildSessionItems(newestFirst([first, pastLimit]));
      expect(headers(items), hasLength(2));
      final breaks = items.whereType<SessionBreakItem>().toList();
      expect(breaks.single.gapSecs, kSessionGap.inSeconds + 1);
    });

    test('separate sessions on different days get a break row, no divider', () {
      final games = newestFirst([
        at(DateTime(2025, 3, 10, 9)),
        at(DateTime(2025, 3, 10, 15)),
        at(DateTime(2025, 3, 11, 10)),
      ]);
      final items = buildSessionItems(games);

      expect(headers(items), hasLength(3));
      expect(items.whereType<DayDividerItem>(), isEmpty);
      expect(items.whereType<SessionBreakItem>(), hasLength(2));
      final i = items.indexWhere(
        (x) => x is SessionHeaderItem && x.start.toLocal().day == 10,
      );
      expect(items[i - 1], isA<SessionBreakItem>());
    });

    test('no divider inside a session that stays within one day', () {
      final games = newestFirst([
        at(DateTime(2025, 3, 10, 9)),
        at(DateTime(2025, 3, 10, 10)),
      ]);
      expect(buildSessionItems(games).whereType<DayDividerItem>(), isEmpty);
    });

    test('a filtered list keeps the sessions of the whole history', () {
      final a = at(DateTime(2025, 3, 10, 10));
      final casual = at(DateTime(2025, 3, 10, 11, 30), ranked: false);
      final b = at(DateTime(2025, 3, 10, 13));
      final pool = newestFirst([a, casual, b]);
      final filtered = newestFirst([a, b]);

      expect(headers(buildSessionItems(filtered)), hasLength(2));
      final withPool = headers(buildSessionItems(filtered, sessionPool: pool));
      expect(withPool, hasLength(1));
      expect(withPool.single.games, 2);
    });

    test('a legend\'s page over the whole history shows no break for time spent '
        'on another legend', () {
      // Axle 10:00, another legend 11:30, Axle 13:00: no break, though the Axle
      // games alone are 2h50 apart.
      final first = at(DateTime(2025, 3, 10, 10));
      final other = at(DateTime(2025, 3, 10, 11, 30));
      final last = at(DateTime(2025, 3, 10, 13));
      final pool = newestFirst([first, other, last]);
      final onePage = newestFirst([first, last]);

      final alone = buildSessionItems(onePage);
      expect(headers(alone), hasLength(2));
      expect(alone.whereType<SessionBreakItem>(), hasLength(1));

      final withPool = buildSessionItems(onePage, sessionPool: pool);
      expect(headers(withPool), hasLength(1));
      expect(withPool.whereType<SessionBreakItem>(), isEmpty);
    });

    test('break rows can be left out when the sessions are not found over '
        'everything played', () {
      final games = newestFirst([
        at(DateTime(2025, 3, 10, 10)),
        at(DateTime(2025, 3, 10, 14)),
      ]);

      expect(
        buildSessionItems(games).whereType<SessionBreakItem>(),
        hasLength(1),
      );
      final without = buildSessionItems(games, includeBreaks: false);
      expect(without.whereType<SessionBreakItem>(), isEmpty);
      // Only the break row goes: both sessions are still there.
      expect(headers(without), hasLength(2));
    });

    test('a page cut never splits a session, even across midnight', () {
      final games = newestFirst([
        for (var i = 0; i < 6; i++) at(DateTime(2025, 3, 10, 23, i * 15)),
        at(DateTime(2025, 3, 9, 12)),
      ]);
      final items = buildSessionItems(games, limit: 3);

      expect(items.whereType<MatchItem>(), hasLength(6));
      expect(headers(items).single.games, 6);
    });

    test('a session keeps its collapse key as newer games join it', () {
      final older = at(DateTime(2025, 3, 10, 10));
      final mid = at(DateTime(2025, 3, 10, 10, 20));
      final newer = at(DateTime(2025, 3, 10, 10, 40));

      final before = headers(
        buildSessionItems(newestFirst([older, mid])),
      ).single;
      final after = headers(
        buildSessionItems(newestFirst([older, mid, newer])),
      ).single;
      expect(after.key, before.key);
    });

    test('the span runs from the first start to the last end', () {
      final games = newestFirst([
        at(DateTime(2025, 3, 10, 23, 30)),
        at(DateTime(2025, 3, 11, 0, 10)),
      ]);
      final h = headers(buildSessionItems(games)).single;
      expect(h.start.toLocal(), DateTime(2025, 3, 10, 23, 30));
      expect(h.end.toLocal(), DateTime(2025, 3, 11, 0, 20));
    });
  });

  group('historyGrewAtFront', () {
    final older = [for (var i = 1; i <= 4; i++) game(dayOffset: 0, slot: i)];
    final newer = game(dayOffset: 0, slot: 9);

    test('new games added at the front are the same list grown', () {
      expect(historyGrewAtFront(older, [newer, ...older]), isTrue);
    });

    test('an unchanged list is not a different one', () {
      expect(historyGrewAtFront(older, [...older]), isTrue);
    });

    test('a narrowed or reordered set is a different one', () {
      expect(historyGrewAtFront(older, older.sublist(1)), isFalse);
      expect(historyGrewAtFront(older, older.reversed.toList()), isFalse);
      expect(historyGrewAtFront(older, [newer, ...older.sublist(1)]), isFalse);
    });

    test('from or to nothing is a different set', () {
      expect(historyGrewAtFront(const [], older), isFalse);
      expect(historyGrewAtFront(older, const []), isFalse);
    });
  });

  group('paging', () {
    // Twenty days of four games each, newest first.
    final history = [
      for (var d = 0; d < 20; d++)
        for (var s = 0; s < 4; s++) game(dayOffset: d, slot: 4 - s),
    ];

    test('a page cut mid-session runs on to the end of that session', () {
      final items = buildSessionItems(history, limit: 6);
      final headers = items.whereType<SessionHeaderItem>().toList();

      expect(items.whereType<MatchItem>().length, 8);
      expect(headers.length, 2);
      expect(
        headers.last.games,
        4,
        reason: 'the last header must not total a half-shown session',
      );
    });

    test('a cut on a session boundary adds nothing', () {
      expect(
        buildSessionItems(history, limit: 8).whereType<MatchItem>().length,
        8,
      );
    });
  });

  group('MatchHistoryList', () {
    // The pinned title shows the span, e.g. "Oct 9 12:10 PM – 12:50 PM".
    final firstSessionTitle = find
        .textContaining(' – ', findRichText: true)
        .first;

    // Eleven days of games, so the pinned headers have something to pin to.
    final matches = [
      for (var d = 0; d < 11; d++)
        for (var s = 0; s < 3; s++) game(dayOffset: d, slot: 3 - s, kills: s),
    ];

    Future<void> pump(WidgetTester tester, ProviderContainer? c) async {
      final container = c ?? ProviderContainer();
      if (c == null) addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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

    testWidgets('collapsing a session hides its matches and keeps its header', (
      tester,
    ) async {
      // Tall enough to build every row, so collapsing can't pull more into view.
      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pump(tester, container);

      expect(firstSessionTitle, findsOneWidget);
      expect(find.text('Axle'), findsWidgets);
      final rowsBefore = find.text('Axle').evaluate().length;

      await tester.tap(firstSessionTitle);
      await tester.pump();
      expect(firstSessionTitle, findsOneWidget);
      expect(find.text('Axle').evaluate().length, lessThan(rowsBefore));

      await tester.tap(firstSessionTitle);
      await tester.pump();
      expect(find.text('Axle').evaluate().length, rowsBefore);
    });

    testWidgets(
      'each session shows its numbers as labelled columns, in full words '
      'rather than a dotted line of abbreviations',
      (tester) async {
        await pump(tester, null);

        for (final label in ['Record', 'Avg RP', 'Kills', 'Damage']) {
          expect(find.text(label), findsWidgets, reason: label);
        }
        // Today: three games, all wins (rich text, so searched as such).
        expect(find.textContaining('3W', findRichText: true), findsWidgets);
        expect(find.textContaining('3 games'), findsWidgets);
        // The old header's "NET" label and average-damage figure are gone (the
        // match rows below still show their own "dmg").
        expect(find.text('NET'), findsNothing);
        expect(find.textContaining('avg dmg'), findsNothing);
      },
    );

    testWidgets('collapsing a session keeps its record but drops the other '
        'columns', (tester) async {
      // Tall enough to build every session, so collapsing one can't pull
      // another into view and keep the count the same.
      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await pump(tester, container);
      final killsBefore = find.text('Kills').evaluate().length;

      await tester.tap(firstSessionTitle);
      await tester.pump();

      expect(find.text('Kills').evaluate().length, killsBefore - 1);
      // The session's record is still there under its title.
      expect(find.textContaining('3W', findRichText: true), findsWidgets);
    });

    testWidgets('an auto-excluded match shows the Excluded tag', (
      tester,
    ) async {
      final reset = [game(dayOffset: 0, slot: 1, rp: -1500)];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MatchHistoryList(matches: reset, onRefresh: () async {}),
            ),
          ),
        ),
      );
      expect(find.text('Excluded'), findsOneWidget);
      expect(find.byType(ExcludedTag), findsOneWidget);
    });

    testWidgets(
      'a match row groups thousands in its RP badge, like every other '
      'RP figure',
      (tester) async {
        final reset = [game(dayOffset: 0, slot: 1, rp: -1500)];
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: MatchHistoryList(matches: reset, onRefresh: () async {}),
              ),
            ),
          ),
        );

        expect(find.text('-1,500 RP'), findsWidgets);
        expect(find.text('-1500 RP'), findsNothing);
      },
    );

    testWidgets('the detail sheet explains an auto-excluded match', (
      tester,
    ) async {
      final reset = [game(dayOffset: 0, slot: 1, rp: -1500)];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MatchHistoryList(matches: reset, onRefresh: () async {}),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Axle'));
      await tester.pumpAndSettle();
      expect(find.byType(ExcludedTag), findsNWidgets(2)); // row + sheet
      expect(find.textContaining('Excluded automatically'), findsOneWidget);
    });

    testWidgets('loads every page when the list is too short to scroll', (
      tester,
    ) async {
      // 80 games over 20 days in a window tall enough to show all: no scroll event fires.
      final long = [
        for (var d = 0; d < 20; d++)
          for (var s = 0; s < 4; s++) game(dayOffset: d, slot: 4 - s),
      ];
      tester.view.physicalSize = const Size(800, 30000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MatchHistoryList(matches: long, onRefresh: () async {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Axle'), findsNWidgets(80));
    });

    testWidgets('a session header gives both dates when it crosses midnight, '
        'and the detail sheet names the weekday', (tester) async {
      RankedMatch at(DateTime start) =>
          buildMatch(start: start.millisecondsSinceEpoch ~/ 1000);
      final games = [
        at(DateTime(2025, 3, 11, 0, 10)),
        at(DateTime(2025, 3, 10, 23, 30)),
      ];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MatchHistoryList(matches: games, onRefresh: () async {}),
            ),
          ),
        ),
      );

      // intl may put a narrow no-break space before AM/PM.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data ?? '')
                  .replaceAll('\u202f', ' ')
                  .startsWith('Mar 10, 2025 11:30 PM – Mar 11, 2025 12:20 AM'),
        ),
        findsOneWidget,
      );
      // The counts sit on their own line, so they never get cut off.
      expect(find.text('2 games · 20m'), findsOneWidget);

      await tester.tap(find.text('Axle').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tuesday, March 11, 2025'), findsOneWidget);
    });

    testWidgets('a session\'s average RP is green when positive and red when '
        'negative', (tester) async {
      Color? colorOf(String text) {
        Color? found;
        for (final e in find.byType(RichText).evaluate()) {
          final rich = e.widget as RichText;
          if (rich.text.toPlainText() != text) continue;
          rich.text.visitChildren((span) {
            if (span is TextSpan && span.text == text) {
              found = span.style?.color;
            }
            return true;
          });
        }
        return found;
      }

      final up = [game(dayOffset: 0, slot: 1, rp: 10)];
      final down = [game(dayOffset: 0, slot: 1, rp: -10)];
      for (final (games, text, color) in [
        (up, '+10.0', AppTheme.green),
        (down, '-10.0', AppTheme.red),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: MatchHistoryList(matches: games, onRefresh: () async {}),
              ),
            ),
          ),
        );
        expect(colorOf(text), color, reason: text);
      }
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

  group('a session no game reported kills or damage for', () {
    Finder noReading() => find.byWidgetPredicate(
      (w) => w is Text && w.textSpan?.toPlainText() == '—',
    );

    testWidgets('shows no reading, not a measured 0', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final games = [
        game(dayOffset: 0, slot: 2, kills: null, damage: null),
        game(dayOffset: 0, slot: 1, kills: null, damage: null),
      ];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MatchHistoryList(matches: games, onRefresh: () async {}),
            ),
          ),
        ),
      );

      // Kills and Damage columns of the one session header.
      expect(noReading(), findsNWidgets(2));
    });
  });

  group('a legend\'s drill-down page', () {
    // Axle at slots 0 and 8 with another legend between: 7400 s apart alone,
    // 3400 s over everything.
    final older = game(dayOffset: 0, slot: 0);
    final between = game(dayOffset: 0, slot: 4, legend: 'Wraith');
    final newer = game(dayOffset: 0, slot: 8);
    final axle = [newer, older]; // newest first
    final everything = [newer, between, older];

    Future<void> pumpScreen(
      WidgetTester tester, {
      List<RankedMatch>? sessionPool,
    }) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: RankedEntityHistoryScreen(
              title: 'Axle',
              subtitle: '2 ranked games',
              matches: axle,
              onRefresh: () async {},
              groupLabel: 'map',
              grouping: MatchGrouping.byMap,
              sessionPool: sessionPool,
            ),
          ),
        ),
      );
    }

    testWidgets('over the split\'s whole history it shows one session and no '
        '"break" for time spent on another legend', (tester) async {
      await pumpScreen(tester, sessionPool: everything);

      expect(find.textContaining('break'), findsNothing);
    });

    testWidgets('with no whole-history list (Lifetime) it names no break it '
        'cannot know', (tester) async {
      await pumpScreen(tester);

      expect(find.textContaining('break'), findsNothing);
    });

    testWidgets('the same two games do show the false break when sessions '
        'are found over them alone', (tester) async {
      // Control: the false break shows without the session pool.
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MatchHistoryList(matches: axle, onRefresh: () async {}),
            ),
          ),
        ),
      );

      expect(find.textContaining('break'), findsOneWidget);
    });
  });

  group('a list embedded in a page', () {
    final games = [
      game(dayOffset: 0, slot: 3),
      game(dayOffset: 0, slot: 2),
      game(dayOffset: 0, slot: 1),
    ];

    Future<void> pumpList(
      WidgetTester tester, {
      Widget? leading,
      bool hideSessionHeaders = false,
    }) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MatchHistoryList(
                matches: games,
                onRefresh: () async {},
                leading: leading,
                hideSessionHeaders: hideSessionHeaders,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows a leading widget above the first row', (tester) async {
      await pumpList(tester, leading: const Text('A page summary'));

      final summary = tester.getTopLeft(find.text('A page summary')).dy;
      final firstRow = tester.getTopLeft(find.text('Axle').first).dy;
      expect(summary, lessThan(firstRow));
    });

    testWidgets('the leading widget scrolls away with the list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MatchHistoryList(
                matches: games,
                onRefresh: () async {},
                leading: const SizedBox(height: 400, child: Text('Summary')),
              ),
            ),
          ),
        ),
      );
      final before = tester.getTopLeft(find.text('Summary')).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
      await tester.pump();

      expect(tester.getTopLeft(find.text('Summary')).dy, lessThan(before - 50));
    });

    testWidgets('keeps the session title unless told to hide it', (
      tester,
    ) async {
      await pumpList(tester);

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.text('Axle'), findsNWidgets(3));
    });

    testWidgets('can hide the session title and stats, keeping every game', (
      tester,
    ) async {
      await pumpList(tester, hideSessionHeaders: true);

      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.text('Axle'), findsNWidgets(3));
    });
  });
}
