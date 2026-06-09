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
}
