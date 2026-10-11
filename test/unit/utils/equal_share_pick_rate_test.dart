import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/screens/ranked/ranked_pick_rate_screen.dart';

void main() {
  group('equalSharePickRate', () {
    test('two mains and a long tail: the line is each main\'s own share', () {
      // 30 games: Bangalore 12, Wraith 12, six other legends with 1 game each.
      // The pool (legends with enough games) is the two mains, so the even
      // split is 40% each - not 50%, which would class both mains as low-pick.
      final line = equalSharePickRate(
        poolGames: 24,
        totalGames: 30,
        poolSize: 2,
      );

      expect(line, closeTo(0.4, 1e-12));
      expect(12 / 30 >= line, isTrue, reason: 'a main is high-pick');
      expect(1 / 30 >= line, isFalse, reason: 'a one-off is not');
    });

    test('a legend at exactly the even share compares equal to the line', () {
      // Matters because the check is `pickRate >= line`.
      final line = equalSharePickRate(
        poolGames: 24,
        totalGames: 30,
        poolSize: 2,
      );

      expect(12 / 30, line);
    });

    test('with nothing hidden it is the plain 1 / count', () {
      expect(
        equalSharePickRate(poolGames: 30, totalGames: 30, poolSize: 3),
        closeTo(1 / 3, 1e-12),
      );
    });
  });
}
