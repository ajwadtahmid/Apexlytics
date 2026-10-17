import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/ranked/session_overview.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// A session that started [hour] hours into the day, with the figures given
/// and no games behind it.
RankedSession _session(
  int hour, {
  required int games,
  required int netRp,
  int minutes = 30,
}) => RankedSession(
  start: DateTime.utc(2026, 9, 1, hour),
  end: DateTime.utc(2026, 9, 1, hour, minutes),
  games: games,
  netRp: netRp,
  totalKills: 0,
  totalDamage: 0,
  killsGames: 0,
  damageGames: 0,
  matches: const [],
);

void main() {
  group('sessionOverview', () {
    test('is null with no sessions', () {
      expect(sessionOverview(const []), isNull);
    });

    test('counts, averages and totals the sessions', () {
      final o = sessionOverview([
        _session(8, games: 4, netRp: 30, minutes: 60),
        _session(12, games: 2, netRp: -10, minutes: 30),
        _session(16, games: 6, netRp: 10, minutes: 90),
      ])!;

      expect(o.count, 3);
      expect(o.avgGames, 4);
      expect(o.avgNetRp, closeTo(10, 1e-9));
      expect(o.totalTime, const Duration(hours: 3));
    });

    test('names the session with the most and the least RP', () {
      final sessions = [
        _session(8, games: 4, netRp: 30),
        _session(12, games: 2, netRp: -40),
        _session(16, games: 6, netRp: 10),
      ];
      final o = sessionOverview(sessions)!;

      expect(o.best, same(sessions[0]));
      expect(o.worst, same(sessions[1]));
    });

    test('does not depend on the order it is given', () {
      final sessions = [
        _session(8, games: 4, netRp: 30),
        _session(12, games: 2, netRp: -40),
      ];
      final o = sessionOverview(sessions.reversed.toList())!;

      expect(o.best, same(sessions[0]));
      expect(o.worst, same(sessions[1]));
    });

    test('a tie on RP goes to the session with more games, then the later', () {
      final a = _session(8, games: 3, netRp: 20);
      final b = _session(12, games: 5, netRp: 20);
      expect(sessionOverview([a, b])!.best, same(b));

      final c = _session(8, games: 4, netRp: 20);
      final d = _session(12, games: 4, netRp: 20);
      expect(sessionOverview([c, d])!.best, same(d));
    });

    test('a single session is the best and has no worst', () {
      final only = _session(8, games: 4, netRp: 30);
      final o = sessionOverview([only])!;

      expect(o.best, same(only));
      expect(o.worst, isNull);
    });

    test('sessions that all net the same have no worst', () {
      final o = sessionOverview([
        _session(8, games: 4, netRp: 20),
        _session(12, games: 4, netRp: 20),
      ])!;

      expect(o.worst, isNull);
    });
  });

  group('a session game by game', () {
    // Played in this order: +10, then -15, then +20.
    final session = sessionize([
      buildMatch(rp: 20, start: 1782090000 + 2 * 1500),
      buildMatch(rp: -15, start: 1782090000 + 1 * 1500),
      buildMatch(rp: 10, start: 1782090000),
    ]).single;

    test('lists each game\'s RP oldest first', () {
      expect(sessionGameRp(session), [10, -15, 20]);
    });

    test('runs the RP total from zero through each game', () {
      expect(sessionRpPath(session), [0, 10, -5, 15]);
    });

    test('a game left out of the stats moves nothing', () {
      final skipped = sessionize([
        buildMatch(rp: 20, start: 1782090000 + 1500),
        buildMatch(rp: 50, start: 1782090000, excluded: true),
      ]).single;

      expect(sessionGameRp(skipped), [0, 20]);
    });
  });

  group('biggestDrop', () {
    test('is the deepest fall from a high point to the low after it', () {
      // Up to 10, down to -5, up to 15, down to 12.
      final drop = biggestDrop([0, 10, -5, 15, 12])!;

      expect((drop.from, drop.to, drop.amount), (1, 2, 15));
    });

    test('measures from the highest point before the low, not the start', () {
      final drop = biggestDrop([0, 30, 20, 5, 25])!;

      expect((drop.from, drop.to, drop.amount), (1, 3, 25));
    });

    test('is null when it only rises or stays level', () {
      expect(biggestDrop([0, 10, 20, 20]), isNull);
      expect(biggestDrop([0]), isNull);
    });

    test('a fall from the start counts', () {
      final drop = biggestDrop([0, -5, -12, -4])!;

      expect((drop.from, drop.to, drop.amount), (0, 2, 12));
    });

    test('the first of two equal falls wins', () {
      final drop = biggestDrop([0, -10, 0, -10])!;

      expect((drop.from, drop.to), (0, 1));
    });
  });

  group('biggestGain', () {
    test('is the biggest rise from a low point to the high after it', () {
      // Down to -5, up to 15, down to 12, up to 20: the rise to 20 is bigger.
      final gain = biggestGain([0, -5, 15, 12, 20])!;

      expect((gain.from, gain.to, gain.amount), (1, 4, 25));
    });

    test('measures from the lowest point before the high, not the start', () {
      final gain = biggestGain([0, -10, -20, 5, 0])!;

      expect((gain.from, gain.to, gain.amount), (2, 3, 25));
    });

    test('is null when it only falls or stays level', () {
      expect(biggestGain([0, -10, -20, -20]), isNull);
      expect(biggestGain([0]), isNull);
    });

    test('a rise from the start counts', () {
      final gain = biggestGain([0, 12, 30, 25])!;

      expect((gain.from, gain.to, gain.amount), (0, 2, 30));
    });

    test('the first of two equal rises wins', () {
      final gain = biggestGain([0, 10, 0, 10])!;

      expect((gain.from, gain.to), (0, 1));
    });
  });

  group('sessionLegendResults', () {
    test('totals each legend and puts the best first', () {
      final session = sessionize([
        buildMatch(legend: 'Loba', rp: -5, start: 1782090000),
        buildMatch(legend: 'Axle', rp: 20, start: 1782090000 + 1500),
        buildMatch(legend: 'Axle', rp: 10, start: 1782090000 + 3000),
      ]).single;

      final results = sessionLegendResults(session);

      expect(results.map((r) => r.legend), ['Axle', 'Loba']);
      expect(results.map((r) => r.games), [2, 1]);
      expect(results.map((r) => r.netRp), [30, -5]);
    });

    test('a tie on RP goes to the legend with more games, then the name', () {
      final session = sessionize([
        buildMatch(legend: 'Wraith', rp: 10, start: 1782090000),
        buildMatch(legend: 'Loba', rp: 5, start: 1782090000 + 1500),
        buildMatch(legend: 'Loba', rp: 5, start: 1782090000 + 3000),
        buildMatch(legend: 'Axle', rp: 10, start: 1782090000 + 4500),
      ]).single;

      expect(sessionLegendResults(session).map((r) => r.legend), [
        'Loba',
        'Axle',
        'Wraith',
      ]);
    });

    test('counts a game left out of the stats, with no RP', () {
      final session = sessionize([
        buildMatch(legend: 'Axle', rp: 50, start: 1782090000, excluded: true),
        buildMatch(legend: 'Axle', rp: 10, start: 1782090000 + 1500),
      ]).single;

      final axle = sessionLegendResults(session).single;
      expect((axle.games, axle.netRp), (2, 10));
    });
  });
}
