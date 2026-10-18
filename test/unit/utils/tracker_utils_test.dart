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
      final trackers = [
        _t('BR Kills', 500),
        _t('BR Kills', 1200),
        _t('BR Kills', 800),
      ];
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

  group('legendCardTrackers', () {
    // Each cell as "label value", a blank as null, a no reading as "label -".
    List<String?> cells(LegendCardTrackers c) => [
      for (final cell in c.cells)
        cell == null ? null : '${cell.label} ${cell.value ?? '-'}',
    ];

    test('is always four cells, kills first on the top row, damage second', () {
      final c = legendCardTrackers([]);

      expect(cells(c), ['BR Kills -', null, 'BR Damage -', null]);
      expect(c.hidden, 0);
    });

    test('fills in kills and damage, whatever order they came in', () {
      final c = legendCardTrackers([_t('BR Damage', 5), _t('BR Kills', 9)]);

      expect(cells(c), ['BR Kills 9', null, 'BR Damage 5', null]);
      expect(c.hidden, 0);
    });

    test('the next trackers sit beside them, in the legend\'s order', () {
      final c = legendCardTrackers([_t('A', 1), _t('BR Kills', 9), _t('B', 2)]);

      expect(cells(c), ['BR Kills 9', 'A 1', 'BR Damage -', 'B 2']);
      expect(c.hidden, 0);
    });

    test('counts what does not fit', () {
      final c = legendCardTrackers([
        _t('BR Kills', 9),
        _t('BR Damage', 5),
        _t('A', 1),
        _t('B', 2),
        _t('C', 3),
        _t('D', 4),
      ]);

      expect(cells(c), ['BR Kills 9', 'A 1', 'BR Damage 5', 'B 2']);
      expect(c.hidden, 2);
    });

    test('a legend with no kills or damage still counts the rest', () {
      final c = legendCardTrackers([_t('A', 1), _t('B', 2), _t('C', 3)]);

      expect(cells(c), ['BR Kills -', 'A 1', 'BR Damage -', 'B 2']);
      expect(c.hidden, 1);
    });

    test('a second kills tracker under the same name takes the higher one', () {
      final c = legendCardTrackers([
        _t('BR Kills', 7606),
        _t('BR Kills', 15557),
        _t('A', 1),
      ]);

      expect(cells(c), ['BR Kills 15557', 'A 1', 'BR Damage -', null]);
      // The other one is on the legend's page.
      expect(c.hidden, 1);
    });

    test('the career card is career kills, wins and revives', () {
      final c = legendCardTrackers([
        _t('Career Revives', 30),
        _t('Career Kills', 500),
        _t('Career Damage', 9),
        _t('Career Wins', 12),
      ], career: true);

      expect(cells(c), [
        'Career Kills 500',
        'Career Wins 12',
        'Career Revives 30',
        null,
      ]);
      expect(c.hidden, 1);
    });

    test('the career trackers are found by key too', () {
      final c = legendCardTrackers([
        const LegendTracker(
          key: 'career_kills',
          displayName: 'Kills',
          value: 5,
        ),
      ], career: true);

      expect(cells(c), [
        'Career Kills 5',
        'Career Wins -',
        'Career Revives -',
        null,
      ]);
      expect(c.hidden, 0);
    });

    test('a career card with none of them is all no readings', () {
      final c = legendCardTrackers([], career: true);

      expect(cells(c), [
        'Career Kills -',
        'Career Wins -',
        'Career Revives -',
        null,
      ]);
    });
  });
}
