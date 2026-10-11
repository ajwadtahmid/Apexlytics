import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/map_rotation.dart';

void main() {
  Map<String, dynamic> block(String map, int secs) => {
    'current': {'map': map, 'remainingSecs': secs},
    'next': {'map': '$map next', 'remainingSecs': 0},
  };

  group('MapRotation.fromJson', () {
    test('reads every mode when the payload is well formed', () {
      final r = MapRotation.fromJson({
        'battle_royale': block('Olympus', 600),
        'ranked': block('Storm Point', 1200),
        'ltm': block('Control', 300),
        'wildcard': block('Wildcard', 900),
      });

      expect(r.battleRoyaleCurrent.map, 'Olympus');
      expect(r.rankedCurrent.remainingSecs, 1200);
      expect(r.ltmCurrent?.map, 'Control');
      expect(r.wildcardNext?.map, 'Wildcard next');
    });

    test('an empty block sent as a list is absent, and the rest still parse',
        () {
      // A PHP-style empty block arrives as [] rather than {} or nothing.
      final r = MapRotation.fromJson({
        'battle_royale': block('Olympus', 600),
        'ranked': block('Storm Point', 1200),
        'ltm': <Object?>[],
        'wildcard': <Object?>[],
      });

      expect(r.battleRoyaleCurrent.map, 'Olympus');
      expect(r.rankedCurrent.map, 'Storm Point');
      expect(r.ltmCurrent, isNull);
      expect(r.ltmNext, isNull);
      expect(r.wildcardCurrent, isNull);
    });

    test('a mode sent as a list parses as an empty one', () {
      final r = MapRotation.fromJson({
        'battle_royale': <Object?>[],
        'ranked': {'current': <Object?>[], 'next': 'soon'},
      });

      expect(r.battleRoyaleCurrent.map, 'Unknown');
      expect(r.rankedCurrent.remainingSecs, 0);
      expect(r.rankedNext.map, 'Unknown');
    });
  });
}
