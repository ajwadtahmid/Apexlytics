import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/formatting/format.dart';

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
}
