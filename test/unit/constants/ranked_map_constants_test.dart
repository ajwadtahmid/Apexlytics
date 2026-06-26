import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/constants/ranked_map_constants.dart';

void main() {
  group('rankedMapName', () {
    test('returns canonical names (incl. correct E-District hyphen)', () {
      expect(rankedMapName('e_district_rotation'), 'E-District');
      // The API's underscore-less spelling must also resolve.
      expect(rankedMapName('edistrict_rotation'), 'E-District');
      expect(rankedMapName('edistrict'), 'E-District');
      expect(rankedMapName('worlds_edge_rotation'), "World's Edge");
      expect(rankedMapName('storm_point_rotation'), 'Storm Point');
    });

    test('handles keys without the _rotation suffix', () {
      expect(rankedMapName('e_district'), 'E-District');
    });

    test('falls back to a title-cased name for unmapped keys', () {
      expect(rankedMapName('some_new_map_rotation'), 'Some New Map');
    });
  });

  group('rankedMapAsset', () {
    test('resolves bundled assets including E-District', () {
      expect(rankedMapAsset('e_district_rotation'), 'assets/maps/e_district.webp');
      expect(rankedMapAsset('edistrict_rotation'), 'assets/maps/e_district.webp');
      expect(rankedMapAsset('olympus_rotation'), 'assets/maps/olympus.webp');
    });

    test('returns null for unmapped/unknown keys', () {
      expect(rankedMapAsset('UNKNOWN'), isNull);
      expect(rankedMapAsset('mystery_rotation'), isNull);
    });
  });

  group('isUnknownMapKey', () {
    test('detects the unknown bucket', () {
      expect(isUnknownMapKey('UNKNOWN'), true);
      expect(isUnknownMapKey(''), true);
      expect(isUnknownMapKey('olympus_rotation'), false);
    });
  });
}
