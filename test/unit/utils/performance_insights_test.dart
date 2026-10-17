import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/ranked/performance_insights.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';

void main() {
  group('trendVerdict', () {
    test(
      'a change inside the band is steady, outside it improving or declining',
      () {
        expect(trendVerdict(0.4, steadyBand: 1), TrendVerdict.steady);
        expect(trendVerdict(-0.4, steadyBand: 1), TrendVerdict.steady);
        expect(trendVerdict(1.0, steadyBand: 1), TrendVerdict.improving);
        expect(trendVerdict(-1.0, steadyBand: 1), TrendVerdict.declining);
      },
    );
  });

  group('rpCaveat', () {
    test('flags a trend whose direction and sign disagree', () {
      expect(rpCaveat(TrendVerdict.improving, -10), 'still losing RP');
      expect(rpCaveat(TrendVerdict.declining, 15), 'still gaining RP');
    });

    test('says nothing when they agree or the trend is steady', () {
      expect(rpCaveat(TrendVerdict.improving, 30), isNull);
      expect(rpCaveat(TrendVerdict.declining, -8), isNull);
      expect(rpCaveat(TrendVerdict.steady, -8), isNull);
      expect(rpCaveat(TrendVerdict.improving, 0), isNull);
    });
  });

  group('dayPartOfHour', () {
    test('covers all 24 hours with the expected edges', () {
      expect(dayPartOfHour(5), DayPart.morning);
      expect(dayPartOfHour(11), DayPart.morning);
      expect(dayPartOfHour(12), DayPart.afternoon);
      expect(dayPartOfHour(16), DayPart.afternoon);
      expect(dayPartOfHour(17), DayPart.evening);
      expect(dayPartOfHour(21), DayPart.evening);
      expect(dayPartOfHour(22), DayPart.night);
      expect(dayPartOfHour(0), DayPart.night);
      expect(dayPartOfHour(4), DayPart.night);
    });
  });

  group('playTimeInsights', () {
    HourBucket hour(int h, int games, int netRp) =>
        HourBucket(hourLocal: h, games: games, netRp: netRp);
    WeekdayBucket day(int d, int games, int netRp) =>
        WeekdayBucket(weekday: d, games: games, netRp: netRp);

    test('names the best and toughest day and part of the day', () {
      final out = playTimeInsights(
        hourBuckets: [
          hour(19, 8, 80), // evening
          hour(20, 8, 80), // evening: 16 games, +10/game
          hour(9, 12, -24), // morning: -2/game
          hour(23, 3, 90), // night: too few games, ignored
        ],
        weekdayBuckets: [day(6, 20, 100), day(1, 12, -36), day(3, 4, 400)],
      );
      expect(out.map((i) => i.heading), [
        'Best day',
        'Toughest day',
        'Best time of day',
        'Toughest time of day',
      ]);
      expect(out[0].name, 'Saturday');
      expect(out[0].avgRp, closeTo(5, 0.001));
      expect(out[1].name, 'Monday');
      expect(out[2].name, 'Evening');
      expect(out[2].detail, '5 – 10 PM');
      expect(out[2].games, 16);
      expect(out[3].name, 'Morning');
    });

    test('says nothing with fewer than two slots that have enough games', () {
      expect(
        playTimeInsights(
          hourBuckets: [hour(19, 30, 300)],
          weekdayBuckets: [day(6, 20, 100), day(1, 9, -36)],
        ),
        isEmpty,
      );
    });

    test('says nothing when the slots are about the same', () {
      expect(
        playTimeInsights(
          hourBuckets: const [],
          weekdayBuckets: [day(6, 20, 40), day(1, 20, 30)], // 2.0 vs 1.5
        ),
        isEmpty,
      );
    });
  });

  group('playTimeInsightsWithFallback', () {
    HourBucket hour(int h, int games, int netRp) =>
        HourBucket(hourLocal: h, games: games, netRp: netRp);
    WeekdayBucket day(int d, int games, int netRp) =>
        WeekdayBucket(weekday: d, games: games, netRp: netRp);

    test('uses the usual bar when it finds something', () {
      final out = playTimeInsightsWithFallback(
        hourBuckets: [hour(19, 12, 120), hour(9, 12, -24)],
        weekdayBuckets: [day(6, 20, 100), day(1, 12, -36)],
      );

      expect(out.insights, isNotEmpty);
      expect(out.lowSample, isFalse);
    });

    test('drops to a lower bar for a player with few games, and says so', () {
      // 6 and 5 games: under 10 a slot, so nothing at the usual bar.
      final hours = [hour(19, 6, 60), hour(9, 5, -25)];
      final days = [day(6, 6, 60), day(1, 5, -25)];

      expect(
        playTimeInsights(hourBuckets: hours, weekdayBuckets: days),
        isEmpty,
      );
      final out = playTimeInsightsWithFallback(
        hourBuckets: hours,
        weekdayBuckets: days,
      );
      expect(out.insights, isNotEmpty);
      expect(out.lowSample, isTrue);
    });

    test('has nothing to report below even the lower bar', () {
      final out = playTimeInsightsWithFallback(
        hourBuckets: [hour(19, 3, 60), hour(9, 2, -25)],
        weekdayBuckets: [day(6, 3, 60), day(1, 2, -25)],
      );

      expect(out.insights, isEmpty);
      expect(out.lowSample, isFalse);
    });
  });

  group('performanceHeadline', () {
    // Newest first. Each session is [netRp] over 2 games.
    List<RankedSession> sessions(List<int> newestFirst) => [
      for (final (i, rp) in newestFirst.indexed)
        RankedSession(
          start: DateTime(2026, 9, 30 - i, 20),
          end: DateTime(2026, 9, 30 - i, 21),
          games: 2,
          netRp: rp,
          totalKills: 0,
          totalDamage: 0,
          killsGames: 0,
          damageGames: 0,
          matches: const [],
        ),
    ];
    const bestDay = PlayInsight(
      heading: 'Best day',
      name: 'Friday',
      avgRp: 8,
      games: 20,
    );
    const bestPart = PlayInsight(
      heading: 'Best time of day',
      name: 'Evening',
      detail: '5 – 10 PM',
      avgRp: 6,
      games: 30,
    );

    test('says how RP per game moved, and when the player does best', () {
      // The last 5 sessions net +20 each, the 5 before -20: from -10 to +10.
      final h = performanceHeadline(
        sessions: sessions([for (var i = 0; i < 10; i++) i < 5 ? 20 : -20]),
        insights: [bestDay, bestPart],
      )!;

      expect(h.trend, 'Up 20.0 RP per game over your last 5 sessions');
      expect(h.verdict, TrendVerdict.improving);
      expect(h.timing, 'You do best on Fridays, in the evening');
    });

    test('a falling trend says down', () {
      final h = performanceHeadline(
        sessions: sessions([for (var i = 0; i < 10; i++) i < 5 ? -20 : 20]),
        insights: const [],
      )!;

      expect(h.trend, 'Down 20.0 RP per game over your last 5 sessions');
      expect(h.verdict, TrendVerdict.declining);
      expect(h.timing, isNull);
    });

    test('a level trend says steady', () {
      final h = performanceHeadline(
        sessions: sessions(List.filled(10, 10)),
        insights: const [],
      )!;

      expect(h.trend, 'Steady over your last 5 sessions');
      expect(h.verdict, TrendVerdict.steady);
    });

    test('needs ten sessions for a trend, but not for the best time', () {
      final h = performanceHeadline(
        sessions: sessions(List.filled(6, 10)),
        insights: [bestDay],
      )!;

      expect(h.trend, isNull);
      expect(h.timing, 'You do best on Fridays');
    });

    test('names a time of day on its own, and night as at night', () {
      expect(
        performanceHeadline(sessions: const [], insights: [bestPart])!.timing,
        'You do best in the evening',
      );
      const night = PlayInsight(
        heading: 'Best time of day',
        name: 'Night',
        avgRp: 4,
        games: 12,
      );
      expect(
        performanceHeadline(sessions: const [], insights: [night])!.timing,
        'You do best at night',
      );
    });

    test('is null with neither a trend nor a best time', () {
      expect(
        performanceHeadline(
          sessions: sessions(List.filled(4, 5)),
          insights: const [],
        ),
        isNull,
      );
    });

    test('ignores the toughest lines', () {
      const toughest = PlayInsight(
        heading: 'Toughest day',
        name: 'Monday',
        avgRp: -5,
        games: 12,
      );
      expect(
        performanceHeadline(sessions: const [], insights: [toughest]),
        isNull,
      );
    });
  });

  group('movingAverage', () {
    SessionReading r(int total, int games) => (total: total, games: games);

    test('averages each session with the two before it, by games not by '
        'session', () {
      // Per-game: 10, 20, 30, 40. The third point covers all of the first
      // three: 120 over 6 games.
      final out = movingAverage([r(20, 2), r(40, 2), r(60, 2), r(80, 2)]);

      expect(out, [10, 15, 20, 30]);
    });

    test('weights a long session more than a short one', () {
      // 0 over 1 game, then 90 over 9: not (0 + 10) / 2.
      final out = movingAverage([r(0, 1), r(90, 9)]);

      expect(out.last, 9);
    });

    test('starts with what it has, so the first point is its own', () {
      expect(movingAverage([r(30, 3), r(60, 3)]).first, 10);
    });

    test('has no reading where the session has none, and skips it in later '
        'windows', () {
      final out = movingAverage([r(10, 1), r(0, 0), r(30, 1)]);

      expect(out[1], isNull);
      expect(out[2], 20); // (10 + 30) over 2 games
    });

    test('takes the window it is given', () {
      final out = movingAverage([r(0, 1), r(10, 1), r(20, 1)], window: 2);

      expect(out, [0, 5, 15]);
    });

    test('is empty for no readings', () {
      expect(movingAverage(const []), isEmpty);
    });
  });

  group('trendWindowChoices', () {
    test('offers a count only with twice as many sessions behind it', () {
      expect(trendWindowChoices(0), isEmpty);
      expect(trendWindowChoices(9), isEmpty);
      expect(trendWindowChoices(10), [5]);
      expect(trendWindowChoices(11), [5]);
      expect(trendWindowChoices(19), [5]);
      expect(trendWindowChoices(20), [5, 10]);
      expect(trendWindowChoices(49), [5, 10]);
      expect(trendWindowChoices(50), [5, 10, 25]);
      expect(trendWindowChoices(99), [5, 10, 25]);
      expect(trendWindowChoices(100), [5, 10, 25, 50]);
      expect(trendWindowChoices(400), [5, 10, 25, 50]);
    });
  });

  group('resolveTrendWindow', () {
    test('uses a saved count that there are sessions for', () {
      expect(resolveTrendWindow(10, 25), (size: 10, compare: 10));
      expect(resolveTrendWindow(5, 12), (size: 5, compare: 5));
    });

    test('narrows a count that is too big to the biggest that fits', () {
      expect(resolveTrendWindow(50, 30), (size: 10, compare: 10));
      expect(resolveTrendWindow(10, 12), (size: 5, compare: 5));
      expect(resolveTrendWindow(25, 20), (size: 10, compare: 10));
    });

    test('All plots every session and compares nothing', () {
      expect(resolveTrendWindow(kTrendWindowAll, 30), (size: null, compare: 0));
    });

    test('with too few sessions for any count, plots all and keeps the '
        'default to say how many are needed', () {
      expect(resolveTrendWindow(10, 6), (size: null, compare: 5));
      expect(resolveTrendWindow(kTrendWindowAll, 6), (size: null, compare: 5));
    });

    test('a count that is not a preset still lands on one', () {
      expect(resolveTrendWindow(7, 30), (size: 5, compare: 5));
    });
  });

  group('performanceHeadline over every session', () {
    List<RankedSession> played(List<int> newestFirst, {int games = 2}) => [
      for (final (i, rp) in newestFirst.indexed)
        RankedSession(
          start: DateTime(2026, 9, 30 - i, 20),
          end: DateTime(2026, 9, 30 - i, 21),
          games: games,
          netRp: rp,
          totalKills: 0,
          totalDamage: 0,
          killsGames: 0,
          damageGames: 0,
          matches: const [],
        ),
    ];

    test('gives the average RP a game, not a change', () {
      // 10 sessions of +10 over 2 games: +5 a game.
      final h = performanceHeadline(
        sessions: played(List.filled(10, 10)),
        insights: const [],
        window: kTrendWindowAll,
      )!;

      expect(h.trend, 'Averaging +5.0 RP per game over all 10 sessions');
      expect(h.average, 5);
      expect(h.verdict, isNull);
    });

    test('a losing average is signed', () {
      final h = performanceHeadline(
        sessions: played(List.filled(10, -6)),
        insights: const [],
        window: kTrendWindowAll,
      )!;

      expect(h.trend, 'Averaging -3.0 RP per game over all 10 sessions');
      expect(h.average, -3);
    });

    test('keeps the best time alongside', () {
      final h = performanceHeadline(
        sessions: played(List.filled(10, 10)),
        insights: const [
          PlayInsight(heading: 'Best day', name: 'Friday', avgRp: 8, games: 20),
        ],
        window: kTrendWindowAll,
      )!;

      expect(h.timing, 'You do best on Fridays');
    });

    test('has no trend without sessions, and a window of ten reads as ten', () {
      expect(
        performanceHeadline(
          sessions: const [],
          insights: const [],
          window: kTrendWindowAll,
        ),
        isNull,
      );
      // The last 10 net +20 each, the 10 before -20.
      final h = performanceHeadline(
        sessions: played([for (var i = 0; i < 20; i++) i < 10 ? 40 : -40]),
        insights: const [],
        window: 10,
      )!;
      expect(h.trend, 'Up 40.0 RP per game over your last 10 sessions');
    });
  });
}
