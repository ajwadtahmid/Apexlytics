import 'package:apexlytics/services/games_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// `/games` answers `200` with match data or `202` with a "no fresh data"
/// envelope. Dio's default `validateStatus` accepts both, so these tests pin the
/// one distinction that keeps a queued response out of the match parser.
void main() {
  group('GamesResult', () {
    test('a pending status of not_tracked is the only actionable one', () {
      const queued = GamesPending(
        status: 'queued',
        retryAfter: Duration(minutes: 5),
      );
      const untracked = GamesPending(
        status: 'not_tracked',
        retryAfter: Duration(minutes: 5),
      );

      expect(queued.isNotTracked, isFalse);
      expect(untracked.isNotTracked, isTrue);
    });

    test('an empty match list is a result, not an absence of one', () {
      const result = GamesMatches([]);

      // The distinction the whole feature rests on: "tracking is live, nothing
      // recorded yet" must not be confused with "we could not fetch".
      expect(result, isA<GamesMatches>());
      expect(result.matches, isEmpty);
      expect(result, isNot(isA<GamesPending>()));
    });

    test('the two outcomes are exhaustively distinguishable', () {
      // A `switch` over the sealed type is how callers are forced to handle
      // both; if a third case is ever added this stops compiling.
      String describe(GamesResult r) => switch (r) {
        GamesMatches(:final matches) => 'matches:${matches.length}',
        GamesPending(:final status) => 'pending:$status',
      };

      expect(describe(const GamesMatches([])), 'matches:0');
      expect(
        describe(
          const GamesPending(status: 'queued', retryAfter: Duration.zero),
        ),
        'pending:queued',
      );
    });
  });
}
