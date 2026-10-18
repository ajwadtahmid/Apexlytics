import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/ranked/recap_journey.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  final t0 = 1782090000;

  /// Games that each move RP by [deltas], from [start], one after another.
  List<RankedMatch> play(List<int> deltas, {int start = 1000}) {
    var rp = start;
    return [
      for (final (i, d) in deltas.indexed)
        buildMatch(start: t0 + i * 1500, rp: d, cumulativeRp: rp += d),
    ];
  }

  test('is null with no ranked games', () {
    expect(recapJourney(const []), isNull);
  });

  test('runs from where the player started to where they finished', () {
    final j = recapJourney(play([20, 30, -10]))!;

    expect([for (final p in j.points) p.rp], [1000, 1020, 1050, 1040]);
    expect([for (final p in j.points) p.game], [0, 1, 2, 3]);
    expect(j.startRp, 1000);
    expect(j.finishRp, 1040);
    expect(j.games, 3);
  });

  test('finds the peak, and says when it is a point of its own', () {
    final j = recapJourney(play([20, 30, -10]))!;

    expect(j.peakRp, 1050);
    expect(j.peakIndex, 2);
    expect(j.peakIsDistinct, isTrue);
  });

  test('a peak at the finish is not a point of its own', () {
    final j = recapJourney(play([10, 10, 10]))!;

    expect(j.peakRp, 1030);
    expect(j.peakIndex, 3);
    expect(j.peakIsDistinct, isFalse);
  });

  test('a peak at the start is not a point of its own', () {
    final j = recapJourney(play([-10, -10]))!;

    expect(j.peakRp, 1000);
    expect(j.peakIndex, 0);
    expect(j.peakIsDistinct, isFalse);
  });

  test('a tie goes to the first time the peak was reached', () {
    final j = recapJourney(play([30, -30, 30]))!;

    expect(j.peakRp, 1030);
    expect(j.peakIndex, 1);
  });

  test('leaves out games that do not count toward the stats', () {
    final games = play([20, 30]);
    final withExcluded = [
      ...games,
      buildMatch(start: t0 + 9000, rp: 99, cumulativeRp: 1149, excluded: true),
    ];

    final j = recapJourney(withExcluded)!;

    expect(j.games, 2);
    expect(j.finishRp, 1050);
  });

  test('does not depend on the order the games come in', () {
    final games = play([20, 30, -10]);

    final a = recapJourney(games)!;
    final b = recapJourney(games.reversed.toList())!;

    expect([for (final p in b.points) p.rp], [for (final p in a.points) p.rp]);
  });

  group('a long period', () {
    // Climbs for 150 games, then falls for 150.
    final deltas = [for (var i = 0; i < 300; i++) i < 150 ? 10 : -5];
    final j = recapJourney(play(deltas), maxPoints: 60)!;

    test('is thinned, but keeps the start, the finish and the peak', () {
      expect(j.points.length, lessThanOrEqualTo(63));
      expect(j.points.first.game, 0);
      expect(j.points.last.game, 300);
      expect(j.peakRp, 1000 + 150 * 10);
      expect(j.points[j.peakIndex].game, 150);
    });

    test('stays in order', () {
      final games = [for (final p in j.points) p.game];
      expect([...games]..sort(), games);
      expect(games.toSet().length, games.length);
    });

    test('still counts every game', () {
      expect(j.games, 300);
    });
  });

  test('a period under the limit is left whole', () {
    final j = recapJourney(play([for (var i = 0; i < 50; i++) 5]))!;

    expect(j.points.length, 51);
  });
}
