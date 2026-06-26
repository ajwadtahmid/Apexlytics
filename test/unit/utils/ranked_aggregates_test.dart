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
          {'key': 'axle_tactical', 'value': 9, 'name': 'Tactical: Nitro Gates Used'},
      ],
      'BRScoreChange': rpChange,
      'BRScore': cumulativeRp,
      'BRRankImg': 'https://x/diamond4.png',
      'isPartyFull': false,
      'map': mapKey,
    });
  }

  // A,B,C in one session; UNKNOWN excluded; E starts ~5h later (new session).
  late List<RankedMatch> data;
  setUp(() {
    data = [
      match(legend: 'Axle', mapKey: 'olympus_rotation', rpChange: 40, cumulativeRp: 1040, kills: 3, damage: 1000, startOffset: 0, axleTracker: true),
      match(legend: 'Axle', mapKey: 'olympus_rotation', rpChange: -20, cumulativeRp: 1020, kills: 1, damage: 500, startOffset: 1800, axleTracker: true),
      match(legend: 'Bangalore', mapKey: 'storm_point_rotation', rpChange: 60, cumulativeRp: 1080, kills: 5, damage: 2000, startOffset: 3600),
      match(legend: 'Octane', mapKey: 'UNKNOWN', rpChange: 0, cumulativeRp: 999999, kills: 0, damage: 0, startOffset: 5400, gameMode: 'UNKNOWN'),
      match(legend: 'Axle', mapKey: 'olympus_rotation', rpChange: 10, cumulativeRp: 1090, kills: 2, damage: 800, startOffset: 18000, axleTracker: true),
    ];
  });

  test('rankedOnly excludes UNKNOWN and sorts newest first', () {
    final r = rankedOnly(data);
    expect(r.length, 4);
    expect(r.first.cumulativeRp, 1090); // most recent (E)
    expect(r.every((m) => m.isRanked), true);
  });

  test('summarize aggregates the window', () {
    final s = summarize(data);
    expect(s.games, 4);
    expect(s.netRp, 90); // 40 - 20 + 60 + 10
    expect(s.currentRp, 1090);
    expect(s.totalKills, 11);
    expect(s.totalDamage, 4300);
    expect(s.avgGameLengthSecs, 600);
  });

  test('summarize on empty input returns empty', () {
    expect(summarize([]).games, 0);
    expect(summarize(const []).currentRp, 0);
  });

  test('legendBreakdowns sorted by total RP desc', () {
    final l = legendBreakdowns(data);
    expect(l.length, 2);
    expect(l.first.legend, 'Bangalore'); // +60 beats Axle's +30
    expect(l.first.totalRp, 60);
    final axle = l.firstWhere((e) => e.legend == 'Axle');
    expect(axle.games, 3);
    expect(axle.totalRp, 30);
    expect(axle.avgRpPerGame, closeTo(10.0, 0.001));
  });

  test('mapBreakdowns sorted by games desc with display names', () {
    final m = mapBreakdowns(data);
    expect(m.length, 2);
    expect(m.first.displayName, 'Olympus');
    expect(m.first.games, 3);
    expect(m.last.displayName, 'Storm Point');
  });

  test('sessionize splits on >2h gaps, newest session first', () {
    final sessions = sessionize(data);
    expect(sessions.length, 2);
    expect(sessions.first.games, 1); // newest = E alone
    expect(sessions.first.netRp, 10);
    expect(sessions[1].games, 3); // A,B,C
    expect(sessions[1].netRp, 80);
  });

  test('aggregateTrackers keeps only high-coverage trackers', () {
    final t = aggregateTrackers(data); // minCoverage 0.8
    // BR Kills + BR Damage are in all 4 (1.0); axle tracker only 3/4 (0.75).
    expect(t.map((e) => e.name), containsAll(['BR Kills', 'BR Damage']));
    expect(t.any((e) => e.name.contains('Nitro')), false);
    final kills = t.firstWhere((e) => e.name == 'BR Kills');
    expect(kills.coverage, 1.0);
    expect(kills.total, 11);
  });

  test('generateInsights surfaces net, best legend, strongest map', () {
    final insights = generateInsights(data);
    final labels = insights.map((i) => i.label).toList();
    expect(labels, contains('Net gain'));
    expect(labels, contains('Best legend'));
    expect(labels, contains('Strongest map'));
    final best = insights.firstWhere((i) => i.label == 'Best legend');
    expect(best.detail, contains('Axle')); // only legend with >=3 games
  });

  test('timeOfDayBuckets covers all ranked games and conserves net RP', () {
    final buckets = timeOfDayBuckets(data);
    final totalGames = buckets.fold<int>(0, (a, b) => a + b.games);
    final totalRp = buckets.fold<int>(0, (a, b) => a + b.netRp);
    expect(totalGames, 4); // UNKNOWN excluded
    expect(totalRp, 90);
    // Hours are device-local; assert each is a valid hour.
    expect(buckets.every((b) => b.hourLocal >= 0 && b.hourLocal <= 23), true);
  });
}
