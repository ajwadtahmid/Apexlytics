import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/utils/formatting/tracker_utils.dart';

LegendTracker _t(String name, int value) =>
    LegendTracker(key: name.toLowerCase(), displayName: name, value: value);

void main() {
  group('deduplicateTrackers', () {
    test('returns empty list for empty input', () {
      expect(deduplicateTrackers([]), isEmpty);
    });

    test('keeps unique trackers unchanged', () {
      final trackers = [_t('Kills', 100), _t('Wins', 50)];
      final result = deduplicateTrackers(trackers);
      expect(result.length, 2);
    });

    test('deduplicates case-insensitively, keeping highest value', () {
      final trackers = [_t('BR Kills', 500), _t('BR Kills', 1200), _t('BR Kills', 800)];
      final result = deduplicateTrackers(trackers);
      expect(result.length, 1);
      expect(result.first.value, 1200);
    });

    test('treats differently-cased display names as same key', () {
      final trackers = [_t('br kills', 100), _t('BR Kills', 200)];
      final result = deduplicateTrackers(trackers);
      expect(result.length, 1);
      expect(result.first.value, 200);
    });
  });

  group('trackerValueMap', () {
    test('returns empty map for empty input', () {
      expect(trackerValueMap([]), isEmpty);
    });

    test('returns correct key-value pairs', () {
      final trackers = [_t('BR Kills', 100), _t('BR Wins', 50)];
      final map = trackerValueMap(trackers);
      expect(map['br kills'], 100);
      expect(map['br wins'], 50);
    });

    test('deduplicates before mapping', () {
      final trackers = [_t('BR Kills', 100), _t('BR Kills', 999)];
      final map = trackerValueMap(trackers);
      expect(map.length, 1);
      expect(map['br kills'], 999);
    });
  });
}
