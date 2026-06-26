import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/formatting/map_name_utils.dart';

void main() {
  group('formatRotationMapName', () {
    test('strips _rotation and title-cases single word', () {
      expect(formatRotationMapName('olympus_rotation'), 'Olympus');
    });

    test('title-cases multi-word maps', () {
      expect(formatRotationMapName('storm_point_rotation'), 'Storm Point');
      expect(formatRotationMapName('kings_canyon_rotation'), 'Kings Canyon');
      expect(formatRotationMapName('broken_moon_rotation'), 'Broken Moon');
    });

    test('maps UNKNOWN (any case) to Unknown', () {
      expect(formatRotationMapName('UNKNOWN'), 'Unknown');
      expect(formatRotationMapName('unknown'), 'Unknown');
    });

    test('handles empty/whitespace input', () {
      expect(formatRotationMapName(''), 'Unknown');
      expect(formatRotationMapName('   '), 'Unknown');
    });

    test('handles a key without the _rotation suffix', () {
      expect(formatRotationMapName('world_edge'), 'World Edge');
    });
  });
}
