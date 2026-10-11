import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/formatting/format.dart';
import 'package:apexlytics/utils/formatting/season_utils.dart'
    show SplitContext;

void main() {
  group('formatNumber', () {
    test('formats zero', () => expect(formatNumber(0), '0'));
    test('formats hundreds', () => expect(formatNumber(999), '999'));
    test(
      'formats thousands with comma',
      () => expect(formatNumber(1000), '1,000'),
    );
    test(
      'formats large numbers',
      () => expect(formatNumber(1234567), '1,234,567'),
    );
  });

  group('calendarDaysBetween', () {
    test('ignores time of day', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 9, 26, 0, 5),
          DateTime(2026, 9, 25, 23, 55),
        ),
        1,
      );
      expect(
        calendarDaysBetween(
          DateTime(2026, 9, 26, 23, 59),
          DateTime(2026, 9, 26),
        ),
        0,
      );
    });

    // Local midnights either side of a DST change are 23 or 25 hours apart;
    // both must still count as exactly one day. Only exercises the transition
    // when the test machine's zone observes DST on these dates (e.g. US
    // zones: 2026-03-08 and 2026-11-01), but holds everywhere.
    test('counts the day either side of a DST change as one day', () {
      expect(
        calendarDaysBetween(DateTime(2026, 3, 9), DateTime(2026, 3, 8)),
        1,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 11, 2), DateTime(2026, 11, 1)),
        1,
      );
    });

    test('crosses month and year boundaries', () {
      expect(
        calendarDaysBetween(DateTime(2027, 1, 1), DateTime(2026, 12, 31)),
        1,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 3, 1), DateTime(2026, 2, 1)),
        28,
      );
    });
  });

  group('formatSigned', () {
    test('adds a + for non-negative values', () {
      expect(formatSigned(4.2), '+4.2');
      expect(formatSigned(0), '+0.0');
    });
    test(
      'leaves the sign alone for negatives',
      () => expect(formatSigned(-4.2), '-4.2'),
    );
    test('a value that rounds to zero is zero, never "-0.0"', () {
      // -1 RP over 30 games is -0.033 per game.
      expect(formatSigned(-1 / 30), '+0.0');
      expect(formatSigned(-0.04), '+0.0');
    });
    test('negative zero is zero, never "+-0.0"', () {
      expect(formatSigned(-0.0), '+0.0');
    });
    test('the first value that rounds away from zero keeps its sign', () {
      expect(formatSigned(-0.06), '-0.1');
      expect(formatSigned(0.06), '+0.1');
    });
  });

  group('formatSignedInt', () {
    test(
      'adds a + and thousands separators',
      () => expect(formatSignedInt(1500), '+1,500'),
    );
    test(
      'leaves negatives alone',
      () => expect(formatSignedInt(-1500), '-1,500'),
    );
  });

  group('capitalize', () {
    test(
      'capitalizes first letter',
      () => expect(capitalize('hello'), 'Hello'),
    );
    test(
      'leaves already-capitalized unchanged',
      () => expect(capitalize('Hello'), 'Hello'),
    );
    test('handles single char', () => expect(capitalize('a'), 'A'));
    test('handles empty string', () => expect(capitalize(''), ''));
    test(
      'capitalizes only first letter',
      () => expect(capitalize('hello world'), 'Hello world'),
    );
  });

  group('timeAgo', () {
    test('returns minutes for recent timestamps', () {
      final ts = DateTime.now().subtract(const Duration(minutes: 30));
      expect(timeAgo(ts), contains('m ago'));
    });

    test('returns hours for timestamps within a day', () {
      final ts = DateTime.now().subtract(const Duration(hours: 5));
      expect(timeAgo(ts), contains('h ago'));
    });

    test('returns days for older timestamps', () {
      final ts = DateTime.now().subtract(const Duration(days: 3));
      expect(timeAgo(ts), contains('d ago'));
    });
  });

  group('formatDuration', () {
    test('minutes only under an hour', () {
      expect(formatDuration(510), '8m'); // 8m 30s → 8m
      expect(formatDuration(0), '0m');
    });

    test('hours and minutes under a day', () {
      expect(formatDuration(30600), '8h 30m');
    });

    test('days and hours over 24h', () {
      expect(formatDuration(90061), '1d 1h');
      expect(formatDuration(8 * 3600), '8h 0m');
    });
  });

  group('splitContextLabel', () {
    SplitContext ctx(int week, int total, Duration remaining) =>
        SplitContext(week: week, totalWeeks: total, remaining: remaining);

    test('week and days remaining', () {
      expect(
        splitContextLabel(ctx(2, 6, const Duration(days: 37))),
        'Week 2 of 6 · Split ends in ~37 days',
      );
    });

    test('truncates part-days, matching in-game display', () {
      expect(
        splitContextLabel(ctx(1, 6, const Duration(days: 36, hours: 22))),
        'Week 1 of 6 · Split ends in ~36 days',
      );
    });

    test('steps to hours rather than reading 0 days under 24h', () {
      expect(
        splitContextLabel(ctx(6, 6, const Duration(hours: 23))),
        'Week 6 of 6 · Split ends in ~23 hours',
      );
    });

    test('singular day', () {
      expect(
        splitContextLabel(ctx(6, 6, const Duration(days: 1))),
        'Week 6 of 6 · Split ends in ~1 day',
      );
    });

    test('falls to hours inside the last day', () {
      expect(
        splitContextLabel(ctx(6, 6, const Duration(hours: 14))),
        'Week 6 of 6 · Split ends in ~14 hours',
      );
    });

    test('falls to minutes inside the last hour', () {
      expect(
        splitContextLabel(ctx(6, 6, const Duration(minutes: 20))),
        'Week 6 of 6 · Split ends in ~20 minutes',
      );
    });

    test('never reads zero on the final approach', () {
      expect(
        splitContextLabel(ctx(6, 6, const Duration(seconds: 5))),
        'Week 6 of 6 · Split ends in ~1 minute',
      );
    });

    test('ended split', () {
      expect(
        splitContextLabel(ctx(6, 6, Duration.zero)),
        'Week 6 of 6 · Split ended',
      );
    });

    test('empty string when there is no split', () {
      expect(splitContextLabel(null), '');
    });
  });

  group('plural', () {
    test('only exactly one is singular', () {
      expect(plural(1, 'game'), '1 game');
      expect(plural(0, 'game'), '0 games');
      expect(plural(2, 'game'), '2 games');
    });

    test('an explicit plural form wins', () {
      expect(plural(1, 'ranked game', 'ranked games'), '1 ranked game');
      expect(plural(3, 'ranked game', 'ranked games'), '3 ranked games');
      expect(plural(2, 'match', 'matches'), '2 matches');
    });
  });

  group('formatPercent', () {
    test('turns a ratio into a percentage', () {
      expect(formatPercent(0.4), '40.0%');
      expect(formatPercent(0), '0.0%');
      expect(formatPercent(1), '100.0%');
      expect(formatPercent(0.3994), '39.9%', reason: 'not rounded up to 40');
    });

    test('keeps the requested decimals', () {
      expect(formatPercent(0.4567, decimals: 1), '45.7%');
      expect(formatPercent(0.4567, decimals: 0), '46%');
    });
  });

  group('kills/damage with no reading', () {
    test('an average that does not exist shows as a dash, not 0', () {
      expect(formatAvgKills(null), kNoReading);
      expect(formatAvgDamage(null), kNoReading);
    });

    test('a real average, including a real zero, is formatted', () {
      expect(formatAvgKills(2.345), '2.3');
      expect(formatAvgKills(0), '0.0');
      expect(formatAvgDamage(1234.6), '1,235');
      expect(formatAvgDamage(0), '0');
    });

    test('a total is a dash only when no game reported it', () {
      expect(formatTotalOrNone(0, 0), kNoReading);
      expect(formatTotalOrNone(0, 5), '0');
      expect(formatTotalOrNone(1500, 3), '1,500');
    });
  });
}
