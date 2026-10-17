import 'package:apexlytics/utils/ranked/matrix_totals.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter_test/flutter_test.dart';

LegendMapCell _cell(String legend, String map, int games, int totalRp) =>
    LegendMapCell(legend: legend, mapName: map, games: games, totalRp: totalRp);

void main() {
  // Alter: 4 on Olympus (+40), 2 on Storm Point (-20).
  // Bangalore: 5 on Olympus (+50).
  final cells = [
    _cell('Alter', 'Olympus', 4, 40),
    _cell('Alter', 'Storm Point', 2, -20),
    _cell('Bangalore', 'Olympus', 5, 50),
  ];

  group('matrixTotals', () {
    final totals = matrixTotals(cells);

    test('adds up each legend over its maps', () {
      expect(totals.byLegend['Alter']!.games, 6);
      expect(totals.byLegend['Alter']!.totalRp, 20);
      expect(totals.byLegend['Alter']!.mapName, kMatrixAll);
      expect(totals.byLegend['Bangalore']!.games, 5);
    });

    test('adds up each map over its legends', () {
      expect(totals.byMap['Olympus']!.games, 9);
      expect(totals.byMap['Olympus']!.totalRp, 90);
      expect(totals.byMap['Olympus']!.legend, kMatrixAll);
      expect(totals.byMap['Storm Point']!.games, 2);
    });

    test('adds up the whole grid, the same from either side', () {
      expect(totals.grand.games, 11);
      expect(totals.grand.totalRp, 70);
      expect(totals.byLegend.values.fold(0, (a, c) => a + c.games), 11);
      expect(totals.byMap.values.fold(0, (a, c) => a + c.totalRp), 70);
    });

    test('RP per game is the total over the games, not a mean of means', () {
      expect(totals.byMap['Olympus']!.avgRpPerGame, 10);
      expect(totals.grand.avgRpPerGame, closeTo(70 / 11, 1e-9));
    });

    test('is empty for no cells', () {
      final none = matrixTotals(const []);

      expect(none.byLegend, isEmpty);
      expect(none.byMap, isEmpty);
      expect(none.grand.games, 0);
    });
  });

  group('orderedMatrixNames', () {
    final totals = matrixTotals([
      _cell('Wraith', 'Olympus', 8, 80), // +10 a game
      _cell('Alter', 'Olympus', 6, 120), // +20 a game
      _cell('Bangalore', 'Olympus', 2, 200), // +100 a game, too few games
      _cell('Axle', 'Olympus', 6, 60), // +10 a game, ties Wraith
    ]);

    List<String> order(MatrixSort s) => orderedMatrixNames(totals.byLegend, s);

    test('most played puts the most games first, ties by name', () {
      expect(order(MatrixSort.mostPlayed), [
        'Wraith',
        'Alter',
        'Axle',
        'Bangalore',
      ]);
    });

    test(
      'best RP puts the best average first among those with enough games',
      () {
        expect(order(MatrixSort.bestRp).take(3), ['Alter', 'Wraith', 'Axle']);
      },
    );

    test('best RP puts a legend with too few games last, however high', () {
      expect(order(MatrixSort.bestRp).last, 'Bangalore');
    });

    test('best RP settles a tie in favour of the more played', () {
      final o = order(MatrixSort.bestRp);

      expect(o.indexOf('Wraith'), lessThan(o.indexOf('Axle')));
    });

    test('A to Z orders by name', () {
      expect(order(MatrixSort.alphabetical), [
        'Alter',
        'Axle',
        'Bangalore',
        'Wraith',
      ]);
    });

    test('orders maps the same way', () {
      final maps = matrixTotals([
        _cell('Alter', 'Storm Point', 6, 120),
        _cell('Alter', 'Olympus', 8, 80),
        _cell('Alter', 'Broken Moon', 5, 5),
      ]);

      expect(orderedMatrixNames(maps.byMap, MatrixSort.mostPlayed), [
        'Olympus',
        'Storm Point',
        'Broken Moon',
      ]);
      expect(orderedMatrixNames(maps.byMap, MatrixSort.bestRp), [
        'Storm Point',
        'Olympus',
        'Broken Moon',
      ]);
    });
  });
}
