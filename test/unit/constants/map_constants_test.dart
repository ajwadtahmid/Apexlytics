import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/constants/map_constants.dart';

void main() {
  group('battleRoyaleMapName', () {
    test('returns canonical names (incl. correct E-District hyphen)', () {
      expect(battleRoyaleMapName('edistrict_rotation'), 'E-District');
      expect(battleRoyaleMapName('edistrict'), 'E-District');
      expect(battleRoyaleMapName('worlds_edge_rotation'), "World's Edge");
      expect(battleRoyaleMapName('storm_point_rotation'), 'Storm Point');
    });

    test('handles keys without the _rotation suffix', () {
      expect(battleRoyaleMapName('edistrict'), 'E-District');
    });

    test('does not special-case the underscored "e_district" spelling', () {
      // Only "edistrict" (no underscore) is mapped — that's the API's
      // confirmed spelling. An underscored variant falls back to the
      // generic title-cased formatter like any other unmapped key.
      expect(battleRoyaleMapName('e_district'), 'E District');
      expect(battleRoyaleMapName('e_district_rotation'), 'E District');
    });

    test('falls back to a title-cased name for unmapped keys', () {
      expect(battleRoyaleMapName('some_new_map_rotation'), 'Some New Map');
    });
  });

  group('battleRoyaleMapInfoByName', () {
    test('finds a map by the display name the rotation API reports', () {
      expect(battleRoyaleMapInfoByName('Kings Canyon')?.id, '1');
      expect(battleRoyaleMapInfoByName("World's Edge")?.id, '2');
      expect(battleRoyaleMapInfoByName('Olympus')?.id, '3');
      expect(battleRoyaleMapInfoByName('Storm Point')?.id, '4');
      expect(battleRoyaleMapInfoByName('Broken Moon')?.id, '5');
      expect(battleRoyaleMapInfoByName('E-District')?.id, '6');
    });

    test('ignores case, punctuation and spacing', () {
      expect(battleRoyaleMapInfoByName("worlds edge")?.name, "World's Edge");
      expect(battleRoyaleMapInfoByName('  e district ')?.name, 'E-District');
      expect(battleRoyaleMapInfoByName("WORLD'S EDGE")?.name, "World's Edge");
    });

    test('is null for a map that is not bundled, e.g. a Mixtape map', () {
      expect(battleRoyaleMapInfoByName('Overflow'), isNull);
      expect(battleRoyaleMapInfoByName('Unknown'), isNull);
      expect(battleRoyaleMapInfoByName(''), isNull);
    });
  });

  group('battleRoyaleMapAsset', () {
    test('resolves bundled assets including E-District', () {
      expect(
        battleRoyaleMapAsset('edistrict_rotation'),
        'assets/maps/e_district.webp',
      );
      expect(
        battleRoyaleMapAsset('olympus_rotation'),
        'assets/maps/olympus.webp',
      );
    });

    test('returns null for unmapped/unknown keys', () {
      expect(battleRoyaleMapAsset('UNKNOWN'), isNull);
      expect(battleRoyaleMapAsset('mystery_rotation'), isNull);
      expect(battleRoyaleMapAsset('e_district_rotation'), isNull);
    });
  });

  group('isUnknownMapKey', () {
    test('detects the unknown bucket', () {
      expect(isUnknownMapKey('UNKNOWN'), true);
      expect(isUnknownMapKey(''), true);
      expect(isUnknownMapKey('olympus_rotation'), false);
    });
  });

  group('kBattleRoyaleMaps', () {
    test('carries a stable id for every catalog entry', () {
      expect(kBattleRoyaleMaps['kings_canyon']?.id, '1');
      expect(kBattleRoyaleMaps['edistrict']?.id, '6');
    });

    test('has exactly one key per map — no e_district alias', () {
      expect(kBattleRoyaleMaps.containsKey('e_district'), false);
      expect(kBattleRoyaleMaps.length, 6);
    });
  });
}
