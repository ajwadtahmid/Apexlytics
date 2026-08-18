import 'package:apexlytics/constants/api_constants.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/services/games_service.dart';
import 'package:apexlytics/utils/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiService extends Mock implements ApiService {}

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

  group('GamesService.getMatches', () {
    late MockApiService mockApi;
    late GamesService service;

    void stubResponse({required int status, required dynamic data}) {
      when(
        () => mockApi.getWithStatus(
          ApiConstants.gamesPath,
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) async => (status: status, data: data));
    }

    setUp(() {
      mockApi = MockApiService();
      service = GamesService(mockApi);
    });

    test('a 200 carrying a list parses into matches', () async {
      stubResponse(status: 200, data: <dynamic>[]);

      final result = await service.getMatches('uid123');

      expect(result, isA<GamesMatches>());
      expect((result as GamesMatches).matches, isEmpty);
    });

    test('a 202 becomes pending with the server\'s retry hint', () async {
      stubResponse(
        status: 202,
        data: {'status': 'not_tracked', 'retryAfterSeconds': 120},
      );

      final result = await service.getMatches('uid123');

      expect(result, isA<GamesPending>());
      final pending = result as GamesPending;
      expect(pending.isNotTracked, isTrue);
      expect(pending.retryAfter, const Duration(seconds: 120));
    });

    test('a 202 without a retry hint falls back to five minutes', () async {
      stubResponse(status: 202, data: {'status': 'queued'});

      final result = await service.getMatches('uid123');

      expect((result as GamesPending).retryAfter, const Duration(minutes: 5));
    });

    test('a 200 carrying a map raises instead of reading as pending', () async {
      // Without this the map would fall through to the 202 branch and report
      // "queued" forever, since no retry hint would ever clear it.
      stubResponse(status: 200, data: {'unexpected': 'shape'});

      expect(() => service.getMatches('uid123'), throwsA(isA<AppException>()));
    });
  });
}
