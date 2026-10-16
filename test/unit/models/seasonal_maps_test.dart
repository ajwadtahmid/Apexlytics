import 'package:apexlytics/models/seasonal_maps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses ranked and pubs maps', () {
    final m = SeasonalMaps.fromJson({
      'ranked': [
        {'id': '3', 'name': 'Olympus'},
      ],
      'pubs': [
        {'id': '2', 'name': "World's Edge"},
      ],
    });
    expect(m.rankedNames, ['Olympus']);
    expect(m.pubsNames, ["World's Edge"]);
  });

  test(
    'a list that is not a list, or entries that are not maps, are skipped',
    () {
      final m = SeasonalMaps.fromJson({
        'ranked': {},
        'pubs': [
          'junk',
          {'id': 2, 'name': 'Olympus'},
        ],
      });
      expect(m.ranked, isEmpty);
      expect(m.pubsNames, ['Olympus']);
      expect(m.pubs.single.id, '');
    },
  );
}
