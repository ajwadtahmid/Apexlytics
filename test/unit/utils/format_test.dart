import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/formatting/format.dart';
import 'package:apexlytics/utils/formatting/season_utils.dart' show SplitContext;

void main() {
  group('formatNumber', () {
    test('formats zero', () => expect(formatNumber(0), '0'));
    test('formats hundreds', () => expect(formatNumber(999), '999'));
    test('formats thousands with comma', () => expect(formatNumber(1000), '1,000'));
    test('formats large numbers', () => expect(formatNumber(1234567), '1,234,567'));
  });

  group('capitalize', () {
    test('capitalizes first letter', () => expect(capitalize('hello'), 'Hello'));
    test('leaves already-capitalized unchanged', () => expect(capitalize('Hello'), 'Hello'));
    test('handles single char', () => expect(capitalize('a'), 'A'));
    test('handles empty string', () => expect(capitalize(''), ''));
    test('capitalizes only first letter', () => expect(capitalize('hello world'), 'Hello world'));
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
}
