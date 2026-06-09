import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/utils/tracking/legend_tracker_logic.dart';

void main() {
  group('findTracker', () {
    const trackers = [
      LegendTracker(key: 'kills', displayName: 'BR Kills', value: 500),
      LegendTracker(key: 'kills2', displayName: 'BR Kills', value: 800),
      LegendTracker(key: 'wins', displayName: 'BR Wins', value: 50),
    ];

    test('returns null when no trackers match', () {
      expect(findTracker(trackers, (t) => t.key == 'damage'), isNull);
    });

    test('returns null for empty list', () {
      expect(findTracker([], (t) => true), isNull);
    });

    test('returns the single matching tracker', () {
      final result = findTracker(trackers, (t) => t.key == 'wins');
      expect(result?.value, 50);
    });

    test('returns the highest-value match when multiple trackers match', () {
      final result = findTracker(trackers, (t) => t.displayName == 'BR Kills');
      expect(result?.value, 800);
    });
  });

  group('findTopWeaponCategories', () {
    LegendTracker cat(String displayName, int value) =>
        LegendTracker(key: displayName, displayName: displayName, value: value);

    test('returns empty list when no weapon-category trackers present', () {
      final trackers = [cat('BR Kills', 100), cat('BR Wins', 10)];
      expect(findTopWeaponCategories(trackers), isEmpty);
    });

    test('returns weapon-category trackers sorted descending', () {
      final trackers = [
        cat('SMG Kills', 200),
        cat('Shotgun Kills', 500),
        cat('LMG Kills', 100),
      ];
      final result = findTopWeaponCategories(trackers);
      expect(result.map((t) => t.value).toList(), [500, 200, 100]);
    });

    test('caps result at kTopWeaponCategories', () {
      final trackers = [
        cat('SMG Kills', 100),
        cat('Shotgun Kills', 200),
        cat('LMG Kills', 300),
        cat('Sniper Kills', 400),
        cat('Pistol Kills', 500),
      ];
      expect(findTopWeaponCategories(trackers).length, kTopWeaponCategories);
    });

    test('does not include non-kill weapon trackers', () {
      final trackers = [
        cat('SMG Damage', 10000),
        cat('Sniper Kills', 50),
      ];
      final result = findTopWeaponCategories(trackers);
      expect(result.length, 1);
      expect(result.first.displayName, 'Sniper Kills');
    });

    test('includes AR kills tracker (apex ar kills key)', () {
      // TrackerKeys.arKills == 'apex ar kills'
      final trackers = [cat('Apex AR Kills', 300)];
      expect(findTopWeaponCategories(trackers), hasLength(1));
    });
  });
}
