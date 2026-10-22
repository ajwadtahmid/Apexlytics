import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/ranked/best_metric.dart';
import 'package:apexlytics/utils/ranked/extra_records.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  /// Unix seconds for a local date and time, so the day a game lands on doesn't
  /// depend on the machine's time zone.
  int at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 10, day, hour, minute).millisecondsSinceEpoch ~/ 1000;

  /// Whether [session] began at [unix] seconds.
  bool startedAt(RankedSession session, int unix) => session.start
      .isAtSameMomentAs(DateTime.fromMillisecondsSinceEpoch(unix * 1000));

  /// One game starting at [start], lasting [length] seconds.
  RankedMatch game(
    int start,
    int rp, {
    int length = 600,
    String legend = 'Axle',
  }) => buildMatch(start: start, rp: rp, length: length, legend: legend);

  /// Games of a session: [rps] one after another, 20 minutes apart.
  List<RankedMatch> run(int start, List<int> rps) => [
    for (var i = 0; i < rps.length; i++) game(start + i * 1200, rps[i]),
  ];

  group('bestDay', () {
    test('is null with no games', () {
      expect(bestDay([]), isNull);
    });

    test('is the day that netted the most RP', () {
      final day = bestDay([
        ...run(at(1, 18), [10, 10]),
        ...run(at(2, 18), [30, -5, 20]),
        ...run(at(3, 18), [15]),
      ]);

      expect(day!.day, DateTime(2026, 10, 2));
      expect(day.netRp, 45);
      expect(day.matches.length, 3);
    });

    test('lists the day\'s games newest first', () {
      final day = bestDay(run(at(2, 18), [10, 20, 30]));

      final ends = [for (final m in day!.matches) m.endTime];
      expect([...ends]..sort((a, b) => b.compareTo(a)), ends);
    });

    test('a day with the same RP but more games wins', () {
      final day = bestDay([
        ...run(at(1, 18), [30]),
        ...run(at(2, 18), [10, 10, 10]),
      ]);

      expect(day!.day, DateTime(2026, 10, 2));
    });

    test('a full tie goes to the later day', () {
      final day = bestDay([
        ...run(at(1, 18), [30]),
        ...run(at(5, 18), [30]),
      ]);

      expect(day!.day, DateTime(2026, 10, 5));
    });

    test('counts a game on the day it ended', () {
      // Starts at 23:55 and ends at 00:05 the next day.
      final day = bestDay([game(at(1, 23, 55), 50)]);

      expect(day!.day, DateTime(2026, 10, 2));
    });

    test('a bad day is never best while a better one exists', () {
      final day = bestDay([
        ...run(at(1, 18), [-20, -10]),
        ...run(at(2, 18), [5]),
      ]);

      expect(day!.netRp, 5);
    });
  });

  group('dayIsSession', () {
    test('is true when the day is exactly the session\'s games', () {
      final games = run(at(1, 18), [10, 20, 30]);
      final session = sessionize(games).single;

      expect(dayIsSession(bestDay(games)!, session), isTrue);
    });

    test('is false when the day holds other games too', () {
      final games = [
        ...run(at(1, 18), [10, 20, 30]),
        ...run(at(1, 23), [5]),
      ];
      final sessions = sessionize(games);
      final best = sessions.reduce((a, b) => a.netRp >= b.netRp ? a : b);

      expect(best.games, 3);
      expect(dayIsSession(bestDay(games)!, best), isFalse);
    });

    test('is false for a different session on another day', () {
      final games = [
        ...run(at(1, 18), [10, 20, 30]),
        ...run(at(2, 18), [5, 5, 5]),
      ];
      final sessions = sessionize(games);
      final other = sessions.firstWhere((s) => s.netRp == 15);

      expect(dayIsSession(bestDay(games)!, other), isFalse);
    });

    test('is false with no session', () {
      expect(dayIsSession(bestDay(run(at(1, 18), [10]))!, null), isFalse);
    });
  });

  group('longestSession', () {
    test('is null with no sessions', () {
      expect(longestSession([]), isNull);
    });

    test('is the one that ran longest from first start to last end', () {
      // Three games over 50 minutes, against two games over 30.
      final sessions = sessionize([
        ...run(at(1, 18), [10, 10, 10]),
        ...run(at(2, 18), [10, 10]),
      ]);

      final longest = longestSession(sessions)!;
      expect(longest.games, 3);
      expect(startedAt(longest, at(1, 18)), isTrue);
    });

    test('a longer session of fewer games still wins on time', () {
      final sessions = sessionize([
        ...run(at(1, 18), [10, 10, 10, 10]),
        // Two long games, 15 minutes apart: one session of over two hours.
        game(at(2, 18), 10, length: 3600),
        game(at(2, 19, 15), 10, length: 3600),
      ]);

      expect(longestSession(sessions)!.games, 2);
    });

    test('a tie goes to the later one', () {
      final tied = sessionize([
        game(at(1, 18), 10, length: 3600),
        game(at(2, 18), 10, length: 3600),
      ]);

      expect(startedAt(longestSession(tied)!, at(2, 18)), isTrue);
    });
  });

  group('biggestComeback', () {
    test('is null with no sessions', () {
      expect(biggestComeback([]), isNull);
    });

    test('is a session that fell below its start and finished above it', () {
      final sessions = sessionize(run(at(1, 18), [-20, -10, 25, 20]));

      final c = biggestComeback(sessions)!;
      // Running: -20, -30, -5, +15.
      expect(c.low, -30);
      expect(c.net, 15);
      expect(c.recovered, 45);
    });

    test('ignores a session that never fell below where it started', () {
      expect(biggestComeback(sessionize(run(at(1, 18), [10, 20, 30]))), isNull);
    });

    test('ignores one that fell and never got back above its start', () {
      expect(
        biggestComeback(sessionize(run(at(1, 18), [-20, 10, -5]))),
        isNull,
      );
    });

    test('ignores one that only got back to where it started', () {
      expect(biggestComeback(sessionize(run(at(1, 18), [-20, 20]))), isNull);
    });

    test('takes the biggest climb back from the low', () {
      final sessions = sessionize([
        ...run(at(1, 18), [-10, 15]), // low -10, net 5: climbed 15
        ...run(at(2, 18), [-30, 10, 30]), // low -30, net 10: climbed 40
      ]);

      final c = biggestComeback(sessions)!;
      expect(c.recovered, 40);
      expect(startedAt(c.session, at(2, 18)), isTrue);
    });

    test('the low is the lowest the session reached, not the first dip', () {
      final c = biggestComeback(sessionize(run(at(1, 18), [-10, 5, -25, 40])))!;

      // Running: -10, -5, -30, +10.
      expect(c.low, -30);
      expect(c.recovered, 40);
    });
  });

  group('topLegendBy', () {
    const perGame = BestMetric.avgRp;

    test('is null with no games', () {
      expect(topLegendBy([], perGame), isNull);
    });

    test('prefers a legend with enough games to a lucky single game', () {
      final games = [
        game(at(1, 18), 10, legend: 'Wraith'),
        game(at(1, 19), 10, legend: 'Wraith'),
        game(at(1, 20), 10, legend: 'Wraith'),
        game(at(1, 21), 40, legend: 'Octane'),
      ];

      // Whatever the measure: one game is not enough to be the top legend.
      expect(topLegendBy(games, perGame), 'Wraith');
      expect(topLegendBy(games, BestMetric.totalRp), 'Wraith');
    });

    test('a measure of the total can favour the legend played more', () {
      final games = [
        // Wraith earns more a game; Octane earns more in all.
        for (var i = 0; i < 3; i++) game(at(1, 10 + i), 10, legend: 'Wraith'),
        for (var i = 0; i < 10; i++) game(at(1, 13 + i), 4, legend: 'Octane'),
      ];

      expect(topLegendBy(games, perGame), 'Wraith');
      expect(topLegendBy(games, BestMetric.totalRp), 'Octane');
    });

    test('with no legend at the minimum, ranks them all', () {
      expect(
        topLegendBy([
          game(at(1, 18), 5, legend: 'Wraith'),
          game(at(1, 19), 5, legend: 'Wraith'),
          game(at(1, 20), 30, legend: 'Octane'),
        ], perGame),
        'Octane',
      );
    });

    test('a tie goes to the legend with more games, then the name', () {
      expect(
        topLegendBy([
          game(at(1, 18), 10, legend: 'Wraith'),
          game(at(1, 19), 10, legend: 'Octane'),
        ], perGame),
        'Octane',
      );
      expect(
        topLegendBy([
          game(at(1, 18), 10, legend: 'Wraith'),
          game(at(1, 19), 10, legend: 'Wraith'),
          game(at(1, 20), 10, legend: 'Octane'),
        ], perGame),
        'Wraith',
      );
    });

    test('is null when no game reported what the measure counts', () {
      expect(
        topLegendBy([
          game(at(1, 18), 10, legend: 'Wraith'),
        ], BestMetric.avgKills),
        isNull,
      );
    });
  });
}
