import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/utils/tracking/legend_calculations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  LegendTracker t(String name, int value) =>
      buildTracker(key: name.toLowerCase(), displayName: name, value: value);

  Map<String, String> calc(List<LegendTracker> trackers) => {
    for (final c in legendCalculations(trackers)) c.label: c.value,
  };

  test('works out every figure from a full set of trackers', () {
    final c = calc([
      t('BR Kills', 1000),
      t('BR Damage', 250000),
      t('BR Wins', 50),
      t('BR Games Played', 400),
      t('BR Revives', 200),
      t('BR Top 3', 100),
      t('BR Kills as Kill Leader', 250),
    ]);

    expect(c, {
      'Damage per Kill': '250',
      'Avg Kills per Game': '2.5',
      'Win Rate': '12.5%',
      'Revive Rate': '0.50',
      'Top 3 Placement %': '25.0%',
      'Kills as Kill Leader %': '25.0%',
    });
  });

  test('keeps the order the page has always shown them in', () {
    final labels = [
      for (final c in legendCalculations([
        t('BR Kills as Kill Leader', 1),
        t('BR Top 3', 1),
        t('BR Revives', 1),
        t('BR Wins', 1),
        t('BR Games Played', 10),
        t('BR Damage', 10),
        t('BR Kills', 10),
      ]))
        c.label,
    ];

    expect(labels, [
      'Damage per Kill',
      'Avg Kills per Game',
      'Win Rate',
      'Revive Rate',
      'Top 3 Placement %',
      'Kills as Kill Leader %',
    ]);
  });

  test('only what the equipped trackers allow', () {
    expect(calc([t('BR Kills', 100), t('BR Damage', 5000)]), {
      'Damage per Kill': '50',
    });
    expect(calc([t('BR Wins', 5), t('BR Games Played', 50)]), {
      'Win Rate': '10.0%',
    });
    expect(calc([]), isEmpty);
  });

  test('never divides by zero', () {
    expect(
      calc([
        t('BR Kills', 0),
        t('BR Damage', 500),
        t('BR Wins', 0),
        t('BR Games Played', 0),
        t('BR Kills as Kill Leader', 0),
      ]),
      isEmpty,
    );
  });

  test('a legend with no kills still has an average of zero a game', () {
    expect(calc([t('BR Kills', 0), t('BR Games Played', 10)]), {
      'Avg Kills per Game': '0.0',
    });
  });

  test('matches names exactly, not by what they contain', () {
    // "BR Season 1 Kills" and "BR Kills as Kill Leader" are not "BR Kills".
    expect(
      calc([
        t('BR Season 1 Kills', 100),
        t('BR Kills as Kill Leader', 50),
        t('BR Damage', 5000),
      ]),
      isEmpty,
    );
  });

  test('a duplicated tracker uses its highest value', () {
    expect(
      calc([t('BR Kills', 50), t('BR Kills', 100), t('BR Damage', 5000)]),
      {'Damage per Kill': '50'},
    );
  });
}
