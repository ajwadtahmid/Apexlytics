import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';

void main() {
  const t0 = 1782090000; // arbitrary fixed epoch (seconds)

  RankedMatch match({
    required String legend,
    required String mapKey,
    required int rpChange,
    required int cumulativeRp,
    required int kills,
    required int damage,
    required int startOffset,
    String gameMode = 'BATTLE_ROYALE',
    bool axleTracker = false,
    int length = 600,
  }) {
    return RankedMatch.fromJson({
      'uid': '1',
      'name': 'Tester',
      'legendPlayed': legend,
      'gameMode': gameMode,
      'gameLengthSecs': length,
      'gameStartTimestamp': t0 + startOffset,
      'gameEndTimestamp': t0 + startOffset + length,
      'gameData': [
        {'key': 'kills', 'value': kills, 'name': 'BR Kills'},
        {'key': 'damage', 'value': damage, 'name': 'BR Damage'},
        if (axleTracker)
          {
            'key': 'axle_tactical',
            'value': 9,
            'name': 'Tactical: Nitro Gates Used',
          },
      ],
      'BRScoreChange': rpChange,
      'BRScore': cumulativeRp,
      'BRRankImg': 'https://x/diamond4.png',
      'isPartyFull': false,
      'map': mapKey,
    });
  }

  // A,B,C in one session; UNKNOWN excluded; E starts ~5h later (new session).
  // Aggregate functions assume pre-filtered input (the caller owns ranked
  // filtering), so tests filter via rankedOnly() before calling them — same
  // as production callers do.
  late List<RankedMatch> data;
  late List<RankedMatch> ranked;
  setUp(() {
    data = [
      match(
        legend: 'Axle',
        mapKey: 'olympus_rotation',
        rpChange: 40,
        cumulativeRp: 1040,
        kills: 3,
        damage: 1000,
        startOffset: 0,
        axleTracker: true,
      ),
      match(
        legend: 'Axle',
        mapKey: 'olympus_rotation',
        rpChange: -20,
        cumulativeRp: 1020,
        kills: 1,
        damage: 500,
        startOffset: 1800,
        axleTracker: true,
      ),
      match(
        legend: 'Bangalore',
        mapKey: 'storm_point_rotation',
        rpChange: 60,
        cumulativeRp: 1080,
        kills: 5,
        damage: 2000,
        startOffset: 3600,
      ),
      match(
        legend: 'Octane',
        mapKey: 'UNKNOWN',
        rpChange: 0,
        cumulativeRp: 999999,
        kills: 0,
        damage: 0,
        startOffset: 5400,
        gameMode: 'UNKNOWN',
      ),
      match(
        legend: 'Axle',
        mapKey: 'olympus_rotation',
        rpChange: 10,
        cumulativeRp: 1090,
        kills: 2,
        damage: 800,
        startOffset: 18000,
        axleTracker: true,
      ),
    ];
    ranked = rankedOnly(data);
  });

  test('rankedOnly excludes UNKNOWN and sorts newest first', () {
    final r = rankedOnly(data);
    expect(r.length, 4);
    expect(r.first.cumulativeRp, 1090); // most recent (E)
    expect(r.every((m) => m.isRanked), true);
  });

  test('summarize aggregates the window', () {
    final s = summarize(ranked);
    expect(s.games, 4);
    expect(s.netRp, 90); // 40 - 20 + 60 + 10
    expect(s.currentRp, 1090);
    expect(s.totalKills, 11);
    expect(s.totalDamage, 4300);
    expect(s.avgGameLengthSecs, 600);
  });

  test('summarize counts wins/losses and win rate from effective RP', () {
    final s = summarize(ranked); // +40, -20, +60, +10
    expect(s.wins, 3);
    expect(s.losses, 1);
    expect(s.decidedGames, 4);
    expect(s.winRate, closeTo(0.75, 0.001));
  });

  test('win/loss ignores RP-neutral and reset-outlier games', () {
    final withResets = rankedOnly([
      match(
        legend: 'Axle',
        mapKey: 'olympus_rotation',
        rpChange: 40,
        cumulativeRp: 40,
        kills: 1,
        damage: 100,
        startOffset: 0,
      ),
      match(
        legend: 'Axle',
        mapKey: 'olympus_rotation',
        rpChange: -20,
        cumulativeRp: 20,
        kills: 1,
        damage: 100,
        startOffset: 60,
      ),
      // End-of-split reset artifact: |rp| >= 1000 → effectiveRpChange 0, so it's
      // neither a win nor a loss (a played game, but RP-neutral).
      match(
        legend: 'Axle',
        mapKey: 'olympus_rotation',
        rpChange: -1500,
        cumulativeRp: 0,
        kills: 0,
        damage: 0,
        startOffset: 120,
      ),
    ]);
    final s = summarize(withResets);
    expect(s.games, 3); // all three are ranked games
    expect(s.wins, 1);
    expect(s.losses, 1);
    expect(s.decidedGames, 2); // the reset game is excluded
    expect(s.winRate, closeTo(0.5, 0.001));
  });

  test('winRate is 0 when there are no decided games', () {
    expect(summarize(const []).winRate, 0);
    expect(RankedSummary.empty.winRate, 0);
  });

  test('summarize on empty input returns empty', () {
    expect(summarize([]).games, 0);
    expect(summarize(const []).currentRp, 0);
  });

  test('legendBreakdowns sorted by total RP desc', () {
    final l = legendBreakdowns(ranked);
    expect(l.length, 2);
    expect(l.first.legend, 'Bangalore'); // +60 beats Axle's +30
    expect(l.first.totalRp, 60);
    final axle = l.firstWhere((e) => e.legend == 'Axle');
    expect(axle.games, 3);
    expect(axle.totalRp, 30);
    expect(axle.avgRpPerGame, closeTo(10.0, 0.001));
    // Axle: +40, -20, +10 → 2W / 1L. Bangalore: +60 → 1W / 0L.
    expect(axle.wins, 2);
    expect(axle.losses, 1);
    expect(axle.winRate, closeTo(2 / 3, 0.001));
    expect(l.first.wins, 1); // Bangalore
    expect(l.first.losses, 0);
    expect(l.first.winRate, 1.0);
  });

  test(
    'legendBreakdowns merges legend-name case variants into one row',
    () {
      // Same reasoning as mapBreakdowns' canonicalization: a raw "axle" vs
      // "Axle" for the same player must not split one legend into two
      // identically-labelled rows.
      final variants = rankedOnly([
        match(
          legend: 'axle',
          mapKey: 'olympus_rotation',
          rpChange: 15,
          cumulativeRp: 1015,
          kills: 1,
          damage: 100,
          startOffset: 0,
        ),
        match(
          legend: 'Axle',
          mapKey: 'olympus_rotation',
          rpChange: 25,
          cumulativeRp: 1040,
          kills: 2,
          damage: 200,
          startOffset: 700,
        ),
      ]);

      final l = legendBreakdowns(variants);

      expect(l.length, 1);
      expect(l.single.legend, 'Axle');
      expect(l.single.games, 2);
      expect(l.single.totalRp, 40);
    },
  );

  test('mapBreakdowns sorted by games desc with display names', () {
    final m = mapBreakdowns(ranked);
    expect(m.length, 2);
    expect(m.first.displayName, 'Olympus');
    expect(m.first.games, 3);
    expect(m.last.displayName, 'Storm Point');
    // Olympus (Axle's 3 games): +40, -20, +10 → 2W / 1L.
    expect(m.first.wins, 2);
    expect(m.first.losses, 1);
    expect(m.first.winRate, closeTo(2 / 3, 0.001));
    // Storm Point (Bangalore's +60): 1W / 0L.
    expect(m.last.wins, 1);
    expect(m.last.losses, 0);
  });

  test('mapBreakdowns merges map-key spelling variants into one row', () {
    // 'edistrict' and 'edistrict_rotation' both name E-District (see
    // kBattleRoyaleMaps) - grouping on the raw key would render two
    // identically labelled "E-District" rows instead of merging their stats.
    final variants = rankedOnly([
      match(
        legend: 'Axle',
        mapKey: 'edistrict',
        rpChange: 20,
        cumulativeRp: 20,
        kills: 1,
        damage: 100,
        startOffset: 0,
      ),
      match(
        legend: 'Axle',
        mapKey: 'edistrict_rotation',
        rpChange: 30,
        cumulativeRp: 50,
        kills: 2,
        damage: 200,
        startOffset: 60,
      ),
    ]);
    final m = mapBreakdowns(variants);
    expect(m.length, 1);
    expect(m.single.displayName, 'E-District');
    expect(m.single.games, 2);
    expect(m.single.totalRp, 50);
    expect(m.single.totalKills, 3);
  });

  test('legendMapBreakdowns groups by legend and map', () {
    final cells = legendMapBreakdowns(ranked);
    expect(cells.length, 2); // Axle+Olympus, Bangalore+Storm Point

    final axleOlympus = cells.firstWhere(
      (c) => c.legend == 'Axle' && c.mapName == 'Olympus',
    );
    expect(axleOlympus.games, 3);
    expect(axleOlympus.totalRp, 30); // +40 - 20 + 10
    expect(axleOlympus.wins, 2);
    expect(axleOlympus.losses, 1);

    final bangaloreStormPoint = cells.firstWhere(
      (c) => c.legend == 'Bangalore' && c.mapName == 'Storm Point',
    );
    expect(bangaloreStormPoint.games, 1);
    expect(bangaloreStormPoint.totalRp, 60);
  });

  test(
    'legendMapBreakdowns drops a legend or map outside the constant lists',
    () {
      final withUnknowns = rankedOnly([
        ...ranked,
        match(
          legend: 'Not A Real Legend',
          mapKey: 'olympus_rotation',
          rpChange: 5,
          cumulativeRp: 1095,
          kills: 1,
          damage: 100,
          startOffset: 90000,
        ),
        match(
          legend: 'Axle',
          mapKey: 'not_a_real_map',
          rpChange: 5,
          cumulativeRp: 1100,
          kills: 1,
          damage: 100,
          startOffset: 93600,
        ),
      ]);
      final cells = legendMapBreakdowns(withUnknowns);
      expect(
        cells.length,
        2,
        reason: 'the unrecognised legend and map each drop their pair entirely',
      );
    },
  );

  test('sessionize splits on >2h gaps, newest session first', () {
    final sessions = sessionize(ranked);
    expect(sessions.length, 2);
    expect(sessions.first.games, 1); // newest = E alone
    expect(sessions.first.netRp, 10);
    expect(sessions[1].games, 3); // A,B,C
    expect(sessions[1].netRp, 80);
  });

  test(
    "sessionize's end is the latest endTime, not the start-sorted last match's",
    () {
      // A starts first but runs long past B's end — upstream reconstructs
      // timestamps from polling gaps, so start order and end order can
      // disagree even within one session.
      final longThenShort = [
        match(
          legend: 'Axle',
          mapKey: 'olympus',
          rpChange: 10,
          cumulativeRp: 1010,
          kills: 1,
          damage: 100,
          startOffset: 0,
          length: 1000,
        ),
        match(
          legend: 'Axle',
          mapKey: 'olympus',
          rpChange: 5,
          cumulativeRp: 1015,
          kills: 1,
          damage: 100,
          startOffset: 100,
          length: 200,
        ),
      ];
      final sessions = sessionize(longThenShort);
      expect(sessions, hasLength(1));
      expect(
        sessions.first.end,
        DateTime.fromMillisecondsSinceEpoch((t0 + 1000) * 1000, isUtc: true),
      );
    },
  );

  test('timeOfDayBuckets covers all ranked games and conserves net RP', () {
    final buckets = timeOfDayBuckets(ranked);
    final totalGames = buckets.fold<int>(0, (a, b) => a + b.games);
    final totalRp = buckets.fold<int>(0, (a, b) => a + b.netRp);
    expect(totalGames, 4); // UNKNOWN excluded
    expect(totalRp, 90);
    // Hours are device-local; assert each is a valid hour.
    expect(buckets.every((b) => b.hourLocal >= 0 && b.hourLocal <= 23), true);
  });

  test('dayOfWeekBuckets covers all ranked games and conserves net RP', () {
    final buckets = dayOfWeekBuckets(ranked);
    final totalGames = buckets.fold<int>(0, (a, b) => a + b.games);
    final totalRp = buckets.fold<int>(0, (a, b) => a + b.netRp);
    expect(totalGames, 4); // UNKNOWN excluded
    expect(totalRp, 90);
    // Weekdays are device-local; assert each is a valid DateTime.weekday value.
    expect(buckets.every((b) => b.weekday >= 1 && b.weekday <= 7), true);
  });

  test(
    'dayOfWeekBucketsFromRankedRows neutralizes outliers like the match path',
    () {
      final rows = [(1782090000000, 40), (1782090000000, -2000)];
      final buckets = dayOfWeekBucketsFromRankedRows(rows);
      final totalRp = buckets.fold<int>(0, (a, b) => a + b.netRp);
      expect(
        totalRp,
        40,
        reason: 'the 2000 RP swing is a reset artifact, zeroed',
      );
      expect(buckets.fold<int>(0, (a, b) => a + b.games), 2);
    },
  );

  group('RankProgress Apex Predator cutoff', () {
    // Master starts at 16000 RP with no upper bound on kRankLadder, so these
    // cases sit at/above that floor to exercise the live-cutoff behaviour.
    RankedSummary summaryAt(int rp) => summarize([
      match(
        legend: 'Axle',
        mapKey: 'olympus_rotation',
        rpChange: 0,
        cumulativeRp: rp,
        kills: 0,
        damage: 0,
        startOffset: 0,
      ),
    ]);

    test('below the live cutoff stays Master, not Predator', () {
      final progress = RankProgress.from(summaryAt(16500), predatorRp: 17000);
      expect(progress.isPredator, false);
      expect(progress.current.label, 'Master');
      expect(progress.next?.label, 'Apex Predator');
    });

    test('crossing the live cutoff flips current to Apex Predator', () {
      final progress = RankProgress.from(summaryAt(17000), predatorRp: 17000);
      expect(progress.isPredator, true);
      expect(progress.current.label, 'Apex Predator');
      expect(progress.next, isNull);
    });

    test('with no cutoff known, Master is never promoted to Predator', () {
      final progress = RankProgress.from(summaryAt(50000), predatorRp: null);
      expect(progress.isPredator, false);
      expect(progress.current.label, 'Master');
      expect(progress.next, isNull);
    });
  });

  group('personalRecords', () {
    test('picks the single best RP/kills/damage game', () {
      final r = personalRecords(ranked);
      expect(r.bestRpGame?.legend, 'Bangalore'); // +60, the highest
      expect(r.bestKillsGame?.legend, 'Bangalore'); // 5 kills, the highest
      expect(r.bestDamageGame?.legend, 'Bangalore'); // 2000 dmg, the highest
    });

    test('best win streak counts consecutive effective-RP wins', () {
      // Chronological: A(+40, win) B(-20, loss) C(+60, win) E(+10, win) —
      // streak resets at B, then runs 2 through C and E.
      final r = personalRecords(ranked);
      expect(r.bestWinStreak, 2);
      expect(r.currentWinStreak, 2);
      // The run that set the record started at C, and it's still ongoing.
      expect(r.bestStreakStart, r.currentStreakStart);
      expect(r.currentStreakStart, ranked[1].startTime); // C, 3rd oldest
    });

    test('an RP-neutral reset-outlier game does not break a win streak', () {
      final withReset = rankedOnly([
        match(
          legend: 'Axle',
          mapKey: 'olympus_rotation',
          rpChange: 40,
          cumulativeRp: 40,
          kills: 1,
          damage: 100,
          startOffset: 0,
        ),
        // |rpChange| >= 1000 → effectiveRpChange 0: neither a win nor a loss.
        match(
          legend: 'Axle',
          mapKey: 'olympus_rotation',
          rpChange: -1500,
          cumulativeRp: 0,
          kills: 0,
          damage: 0,
          startOffset: 60,
        ),
        match(
          legend: 'Axle',
          mapKey: 'olympus_rotation',
          rpChange: 30,
          cumulativeRp: 30,
          kills: 1,
          damage: 100,
          startOffset: 120,
        ),
      ]);
      final r = personalRecords(withReset);
      expect(r.currentWinStreak, 2);
      expect(r.bestWinStreak, 2);
    });

    test('a loss (even -1) breaks a win streak', () {
      final withSmallLoss = rankedOnly([
        match(
          legend: 'Axle',
          mapKey: 'olympus_rotation',
          rpChange: 40,
          cumulativeRp: 40,
          kills: 1,
          damage: 100,
          startOffset: 0,
        ),
        match(
          legend: 'Axle',
          mapKey: 'olympus_rotation',
          rpChange: -1,
          cumulativeRp: 39,
          kills: 1,
          damage: 100,
          startOffset: 60,
        ),
      ]);
      final r = personalRecords(withSmallLoss);
      expect(r.currentWinStreak, 0);
      expect(r.currentStreakStart, isNull);
      expect(r.bestWinStreak, 1);
    });

    test('a match with no reported kills/damage never wins those records', () {
      final noTrackers = RankedMatch.fromJson({
        'uid': '1',
        'name': 'Tester',
        'legendPlayed': 'Wraith',
        'gameMode': 'BATTLE_ROYALE',
        'gameLengthSecs': 600,
        'gameStartTimestamp': t0 + 21600,
        'gameEndTimestamp': t0 + 22200,
        'gameData': <Map<String, Object?>>[],
        'BRScoreChange': 5,
        'BRScore': 1095,
        'BRRankImg': 'https://x/diamond4.png',
        'isPartyFull': false,
        'map': 'olympus_rotation',
      });
      expect(noTrackers.kills, isNull);
      expect(noTrackers.damage, isNull);

      final r = personalRecords([...ranked, noTrackers]);
      expect(r.bestKillsGame?.legend, 'Bangalore');
      expect(r.bestDamageGame?.legend, 'Bangalore');
    });

    test('empty input yields no records and zero streaks', () {
      final r = personalRecords(const []);
      expect(r.bestRpGame, isNull);
      expect(r.bestKillsGame, isNull);
      expect(r.bestDamageGame, isNull);
      expect(r.currentWinStreak, 0);
      expect(r.bestWinStreak, 0);
    });
  });

  group('sessionTrend', () {
    test('returns null below window * 2 sessions', () {
      final sessions = sessionize(ranked); // only 2 sessions in the fixture
      final t = sessionTrend(
        sessions,
        totalOf: (s) => s.netRp,
        gamesOf: (s) => s.games,
        window: 3,
      );
      expect(t, isNull);
    });

    test('averages recent vs previous windows by RP/game', () {
      // Six single-game sessions, each > kSessionGap apart, oldest first:
      // -10, +10, +20, +40, +50, +60 RP. Newest-first once sessionized.
      final sixSessions = rankedOnly([
        for (final (i, rp) in const [-10, 10, 20, 40, 50, 60].indexed)
          match(
            legend: 'Axle',
            mapKey: 'olympus_rotation',
            rpChange: rp,
            cumulativeRp: 1000 + rp,
            kills: 1,
            damage: 100,
            startOffset: i * 10800, // 3h apart — always a new session
          ),
      ]);
      final sessions = sessionize(sixSessions);
      expect(sessions.length, 6);

      final t = sessionTrend(
        sessions,
        totalOf: (s) => s.netRp,
        gamesOf: (s) => s.games,
        window: 3,
      );
      // Recent 3 (newest first): +60, +50, +40 → avg 50.
      // Previous 3: +20, +10, -10 → avg ~6.67.
      expect(t, isNotNull);
      expect(t!.recent, closeTo(50, 0.01));
      expect(t.previous, closeTo(6.6667, 0.01));
      expect(t.delta, closeTo(43.33, 0.01));
    });
  });
}
