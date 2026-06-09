import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/utils/formatting/weapon_utils.dart';

void main() {
  group('findWeaponFromTracker', () {
    test('returns null for a non-weapon tracker name', () {
      expect(findWeaponFromTracker('BR Kills'), isNull);
      expect(findWeaponFromTracker('Wins'), isNull);
      expect(findWeaponFromTracker('Revives'), isNull);
    });

    test('finds a weapon by its primary name', () {
      final result = findWeaponFromTracker('R-301 Kills');
      expect(result, isNotNull);
      expect(result!.name.toLowerCase(), contains('r-301'));
    });

    test('finds a weapon by full name', () {
      final result = findWeaponFromTracker('R-301 Carbine Kills');
      expect(result, isNotNull);
    });

    test('does not match a partial word (boundary check)', () {
      // 'car' is an alt-name for C.A.R. SMG;
      // 'career' must NOT match it.
      expect(findWeaponFromTracker('career kills'), isNull);
    });

    test('is case-insensitive', () {
      final lower = findWeaponFromTracker('r-301 kills');
      final upper = findWeaponFromTracker('R-301 kills');
      expect(lower, isNotNull);
      expect(lower!.name, upper!.name);
    });

    test('prefers longer (more specific) match', () {
      // R-301 Carbine should be preferred over just R-301
      final result = findWeaponFromTracker('R-301 Carbine Damage');
      expect(result, isNotNull);
    });
  });

  group('extractWeaponStats', () {
    LegendTracker tracker(String name, int value) =>
        LegendTracker(key: name, displayName: name, value: value);

    test('returns empty map when no weapon trackers present', () {
      final legends = [
        LegendStat(name: 'Wraith', trackers: [tracker('BR Kills', 100)]),
      ];
      expect(extractWeaponStats(legends), isEmpty);
    });

    test('aggregates weapon trackers across legends', () {
      final legends = [
        LegendStat(name: 'Wraith', trackers: [tracker('R-301 Kills', 200)]),
        LegendStat(name: 'Bangalore', trackers: [tracker('R-301 Kills', 150)]),
      ];
      final result = extractWeaponStats(legends);
      expect(result.length, 1);
      final statKey = result.values.first.keys.first;
      expect(result.values.first[statKey], 200);
    });

    test('keeps the highest value across legends for the same stat', () {
      final legends = [
        LegendStat(name: 'Wraith', trackers: [tracker('R-301 Kills', 300)]),
        LegendStat(name: 'Bangalore', trackers: [tracker('R-301 Kills', 100)]),
      ];
      final result = extractWeaponStats(legends);
      final bucket = result.values.first;
      expect(bucket.values.first, 300);
    });

    test('collects multiple stats for the same weapon', () {
      final legends = [
        LegendStat(name: 'Wraith', trackers: [
          tracker('R-301 Kills', 100),
          tracker('R-301 Damage', 50000),
        ]),
      ];
      final result = extractWeaponStats(legends);
      expect(result.values.first.length, 2);
    });
  });
}
