import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/utils/ranked/entity_trend_window.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('resolveEntityTrendWindow', () {
    test('has no window with too few games to compare', () {
      for (final choice in [kEntityTrendAuto, ...kEntityTrendPresets]) {
        for (final games in [0, 1, 9]) {
          expect(
            resolveEntityTrendWindow(choice, games),
            isNull,
            reason: 'choice $choice, $games games',
          );
        }
      }
    });

    group('on Auto', () {
      // About a quarter of the games, from 5 to 100.
      for (final (games, recent) in [
        (10, 5), // a quarter would be 3: the floor
        (12, 5),
        (35, 9),
        (100, 25),
        (200, 50),
        (400, 100),
        (1500, 100), // a quarter would be 375: the cap
        (12000, 100),
      ]) {
        test('$games games compare their newest $recent', () {
          final window = resolveEntityTrendWindow(kEntityTrendAuto, games)!;
          expect(window.recent, recent);
        });
      }

      test('never takes more than half of the games', () {
        for (var games = 10; games <= 400; games++) {
          final window = resolveEntityTrendWindow(kEntityTrendAuto, games)!;
          expect(window.recent * 2, lessThanOrEqualTo(games), reason: '$games');
        }
      });
    });

    group('on a chosen count', () {
      for (final (choice, games) in [
        (10, 20),
        (25, 60),
        (50, 100),
        (100, 200),
        (37, 80), // typed in
        (500, 1000),
      ]) {
        test('$choice is used with $games games', () {
          expect(resolveEntityTrendWindow(choice, games)!.recent, choice);
        });
      }

      for (final (choice, games, used) in [
        (25, 40, 20), // never more than half
        (50, 45, 22),
        (100, 120, 60),
        (500, 600, 300),
        (1000, 1500, 750),
        (10, 12, 6),
        (5, 10, 5),
      ]) {
        test('$choice is held to $used with only $games games', () {
          expect(resolveEntityTrendWindow(choice, games)!.recent, used);
        });
      }
    });
  });

  group('the range a window can be typed in', () {
    test('is 5 to 1,000, or Auto', () {
      expect(isTrendChoice(kEntityTrendAuto), isTrue);
      for (final ok in [5, 6, 37, 100, 999, 1000]) {
        expect(isTrendChoice(ok), isTrue, reason: '$ok');
      }
      for (final bad in [-1, 1, 4, 1001, 100000]) {
        expect(isTrendChoice(bad), isFalse, reason: '$bad');
      }
    });

    test('is limited, for one legend or map, to half its games', () {
      expect(maxTrendWindow(10), 5);
      expect(maxTrendWindow(500), 250);
      expect(maxTrendWindow(501), 250);
      expect(maxTrendWindow(5000), 1000); // and never past the most
    });
  });

  group('EntityTrendReadingCache', () {
    List<RankedMatch> games(int count) => [
      for (var i = 0; i < count; i++)
        buildMatch(start: 1782090000 + i * 10000, rp: i + 1),
    ];

    test('gives back the same reading for the same games and window', () {
      final cache = EntityTrendReadingCache();
      final matches = games(40);

      final first = cache.read(matches, kEntityTrendAuto);

      expect(identical(cache.read(matches, kEntityTrendAuto), first), isTrue);
    });

    test('works it out again when the window changes', () {
      final cache = EntityTrendReadingCache();
      final matches = games(60);

      final auto = cache.read(matches, kEntityTrendAuto);
      final fifty = cache.read(matches, 25);

      expect(identical(auto, fifty), isFalse);
      expect(fifty.window, (recent: 25));
      // And back again, to a fresh and correct one.
      expect(cache.read(matches, kEntityTrendAuto).window, auto.window);
    });

    test('works it out again for other games', () {
      final cache = EntityTrendReadingCache();

      final first = cache.read(games(40), kEntityTrendAuto);
      final second = cache.read(games(80), kEntityTrendAuto);

      expect(first.window, (recent: 10));
      expect(second.window, (recent: 20));
    });

    test('is what entityTrendReading says', () {
      final cache = EntityTrendReadingCache();
      final matches = games(40);

      final cached = cache.read(matches, 10);
      final direct = entityTrendReading(matches, 10);

      expect(cached.window, direct.window);
      expect(cached.trends.rp!.recent, direct.trends.rp!.recent);
      expect(cached.trends.rp!.overall, direct.trends.rp!.overall);
    });
  });

  group('entityTrendReading', () {
    List<RankedMatch> games(int count) => [
      for (var i = 0; i < count; i++)
        buildMatch(
          start: 1782090000 + i * 10000,
          rp: i + 1,
          kills: 2,
          damage: 300,
        ),
    ];

    test('has no window, and no trends, with too few games', () {
      final reading = entityTrendReading(games(9), kEntityTrendAuto);

      expect(reading.window, isNull);
      expect(reading.trends.rp, isNull);
      expect(reading.trends.kills, isNull);
      expect(reading.trends.damage, isNull);
    });

    test('reads the trends over the window it chose', () {
      final reading = entityTrendReading(games(40), kEntityTrendAuto);

      // A quarter of 40: the newest 10 against the average of all 40.
      expect(reading.window, (recent: 10));
      expect(reading.trends.rp!.delta, greaterThan(0));
    });

    test('follows a chosen count', () {
      final reading = entityTrendReading(games(60), 25);

      expect(reading.window, (recent: 25));
    });
  });
}
