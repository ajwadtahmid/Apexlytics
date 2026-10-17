import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/ranked/legend_table_sort.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

List<RankedMatch> _games(
  String legend,
  int n,
  int rp, {
  int? kills,
  int? damage,
}) => [
  for (var i = 0; i < n; i++)
    buildMatch(
      legend: legend,
      rp: rp,
      kills: kills,
      damage: damage,
      start: 1782090000 + legend.hashCode % 1000 + i * 5000,
    ),
];

void main() {
  // Alter: 6 games, -5 RP each. Bangalore: 3 games, +20. Wraith: 4 games, 0,
  // and no kills or damage reported.
  final legends = legendBreakdowns([
    ..._games('Alter', 6, -5, kills: 4, damage: 900),
    ..._games('Bangalore', 3, 20, kills: 1, damage: 300),
    ..._games('Wraith', 4, 0),
  ]);

  List<String> order(LegendSort sort, {required bool descending}) => [
    for (final l in sortLegends(legends, sort, descending: descending))
      l.legend,
  ];

  test('pick puts the most played first, or last', () {
    expect(order(LegendSort.pick, descending: true), [
      'Alter',
      'Wraith',
      'Bangalore',
    ]);
    expect(order(LegendSort.pick, descending: false), [
      'Bangalore',
      'Wraith',
      'Alter',
    ]);
  });

  test('RP per game and net RP order by the signed value', () {
    expect(order(LegendSort.rpPerGame, descending: true), [
      'Bangalore',
      'Wraith',
      'Alter',
    ]);
    expect(order(LegendSort.netRp, descending: true), [
      'Bangalore',
      'Wraith',
      'Alter',
    ]);
  });

  test('names go A to Z, or Z to A', () {
    expect(order(LegendSort.legend, descending: false), [
      'Alter',
      'Bangalore',
      'Wraith',
    ]);
    expect(order(LegendSort.legend, descending: true), [
      'Wraith',
      'Bangalore',
      'Alter',
    ]);
  });

  test('a legend with no kills or damage reading is last either way', () {
    for (final sort in [LegendSort.kills, LegendSort.damage]) {
      for (final descending in [true, false]) {
        expect(order(sort, descending: descending).last, 'Wraith');
      }
    }
    expect(order(LegendSort.kills, descending: true), [
      'Alter',
      'Bangalore',
      'Wraith',
    ]);
    expect(order(LegendSort.kills, descending: false), [
      'Bangalore',
      'Alter',
      'Wraith',
    ]);
  });

  test('a tie goes to the more played legend, then the name', () {
    final tied = legendBreakdowns([
      ..._games('Zed', 5, 10),
      ..._games('Alter', 5, 10),
      ..._games('Mirage', 7, 10),
    ]);

    expect(
      [
        for (final l in sortLegends(
          tied,
          LegendSort.rpPerGame,
          descending: true,
        ))
          l.legend,
      ],
      ['Mirage', 'Alter', 'Zed'],
    );
  });

  test('does not change the list it is given', () {
    final before = [for (final l in legends) l.legend];

    sortLegends(legends, LegendSort.legend, descending: true);

    expect([for (final l in legends) l.legend], before);
  });

  test('only names start ascending', () {
    expect(LegendSort.legend.startsDescending, isFalse);
    for (final s in LegendSort.values.where((s) => s != LegendSort.legend)) {
      expect(s.startsDescending, isTrue);
    }
  });
}
