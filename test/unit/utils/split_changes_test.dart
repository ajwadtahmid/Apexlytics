import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/ranked/split_changes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

List<RankedMatch> _games(String legend, String map, int n, int rp) => [
  for (var i = 0; i < n; i++)
    buildMatch(
      legend: legend,
      map: map,
      rp: rp,
      start: 1782090000 + legend.hashCode % 1000 + i * 5000,
    ),
];

List<LegendBreakdown> _legends(List<RankedMatch> m) => legendBreakdowns(m);
List<MapBreakdown> _maps(List<RankedMatch> m) => mapBreakdowns(m);

void main() {
  group('pickRateShifts', () {
    // Axle 60% and Bangalore 40%, then Axle 20% and Wraith 80%.
    final before = _legends([
      ..._games('Axle', 'olympus_rotation', 6, 10),
      ..._games('Bangalore', 'olympus_rotation', 4, 10),
    ]);
    final after = _legends([
      ..._games('Axle', 'olympus_rotation', 2, 10),
      ..._games('Wraith', 'olympus_rotation', 8, 10),
    ]);

    test('orders the legends by how far their share moved', () {
      final shifts = pickRateShifts(before, after);

      expect(shifts.map((s) => s.legend), ['Wraith', 'Axle', 'Bangalore']);
      expect(shifts.map(pointsMoved), [80, -40, -40]);
    });

    test('counts a legend missing from one split as zero there', () {
      final wraith = pickRateShifts(before, after).first;
      expect(wraith.before, 0);
      expect(wraith.after, closeTo(0.8, 1e-9));
    });

    test('keeps only the biggest few', () {
      expect(pickRateShifts(before, after, limit: 1), hasLength(1));
    });

    test('leaves out a share that moved by less than a point', () {
      final same = _legends([..._games('Axle', 'olympus_rotation', 4, 10)]);
      expect(pickRateShifts(same, same), isEmpty);
    });

    test('says nothing when either split has no games', () {
      expect(pickRateShifts(const [], after), isEmpty);
      expect(pickRateShifts(before, const []), isEmpty);
    });
  });

  group('mapRpShifts', () {
    final before = _maps([
      ..._games('Axle', 'olympus_rotation', 4, 10),
      ..._games('Axle', 'storm_point_rotation', 4, 5),
      ..._games('Axle', 'kings_canyon_rotation', 4, 5),
    ]);
    final after = _maps([
      ..._games('Axle', 'olympus_rotation', 4, -5),
      // Too few games here to read anything into.
      ..._games('Axle', 'storm_point_rotation', 2, -20),
      // Not played before.
      ..._games('Axle', 'worlds_edge_rotation', 5, 20),
    ]);

    test('compares the maps played enough in both, and only those', () {
      final shifts = mapRpShifts(before, after);

      expect(shifts, hasLength(1));
      expect(shifts.single.map, 'Olympus');
      expect(shifts.single.before, 10);
      expect(shifts.single.after, -5);
    });

    test('puts the biggest swing first, up or down', () {
      final flat = _maps([
        ..._games('Axle', 'olympus_rotation', 3, 0),
        ..._games('Axle', 'storm_point_rotation', 3, 0),
      ]);
      final moved = _maps([
        ..._games('Axle', 'olympus_rotation', 3, 4),
        ..._games('Axle', 'storm_point_rotation', 3, -12),
      ]);

      expect(mapRpShifts(flat, moved).map((s) => s.map), [
        'Storm Point',
        'Olympus',
      ]);
    });

    test('leaves out a map that did not move', () {
      expect(mapRpShifts(before, before), isEmpty);
    });
  });
}
