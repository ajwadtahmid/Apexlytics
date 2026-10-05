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
}
