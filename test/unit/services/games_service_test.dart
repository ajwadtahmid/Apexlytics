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
          failover: false,
        ),
      ).thenAnswer((_) async => (status: status, data: data));
    }

    setUp(() {
      mockApi = MockApiService();
      service = GamesService(mockApi);
    });

    test('sends the owner token header only when a token is stored', () async {
      when(
        () => mockApi.getWithStatus(
          ApiConstants.gamesPath,
          params: any(named: 'params'),
          failover: false,
          headers: {ApiConstants.ownerTokenHeader: 'secret'},
        ),
      ).thenAnswer((_) async => (status: 200, data: <dynamic>[]));

      final owner = GamesService(mockApi, ownerToken: () async => 'secret');
      final result = await owner.getMatches('uid123');

      expect(result, isA<GamesMatches>());
      verify(
        () => mockApi.getWithStatus(
          ApiConstants.gamesPath,
          params: any(named: 'params'),
          failover: false,
          headers: {ApiConstants.ownerTokenHeader: 'secret'},
        ),
      ).called(1);
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

    test('a claim_rate 202 stays a queued, non-error result and keeps the '
        'server\'s 10 to 60 second hint exactly', () async {
      // The server's global claim-rate refusal: a slot is free, but too many
      // claims landed in the last minute. Its hint is 10 to 60 seconds.
      for (final seconds in [10, 25, 60]) {
        stubResponse(
          status: 202,
          data: {
            'status': 'queued',
            'uid': '1000000000001',
            'position': 1,
            'reason': 'claim_rate',
            'retryAfterSeconds': seconds,
            'windowResetsAt': 1790000000000,
          },
        );

        final result = await service.getMatches('uid123');

        expect(result, isA<GamesPending>(), reason: '${seconds}s');
        final pending = result as GamesPending;
        expect(pending.status, 'queued');
        expect(pending.isNotTracked, isFalse);
        expect(pending.reason, 'claim_rate');
        expect(pending.isBriefThrottle, isTrue);
        expect(pending.retryAfter, Duration(seconds: seconds));
      }
    });

    test('any other reason, known or not yet invented, is a plain queue and '
        'never an error', () async {
      for (final reason in [
        'full',
        'rank',
        'locked',
        'client_limit',
        'some_future_reason',
        null,
      ]) {
        stubResponse(
          status: 202,
          data: {
            'status': 'queued',
            'reason': ?reason,
            'retryAfterSeconds': 90,
          },
        );

        final result = await service.getMatches('uid123');

        final pending = result as GamesPending;
        expect(pending.isBriefThrottle, isFalse, reason: '$reason');
        expect(pending.isNotTracked, isFalse, reason: '$reason');
        expect(pending.retryAfter, const Duration(seconds: 90));
      }
    });

    test('a 202 without a retry hint falls back to five minutes', () async {
      stubResponse(status: 202, data: {'status': 'queued'});

      final result = await service.getMatches('uid123');

      expect((result as GamesPending).retryAfter, const Duration(minutes: 5));
    });

    // A row in the shape upstream serves, for the player [uid].
    Map<String, dynamic> row(String uid, {Object? start = 1782090000}) => {
      'uid': uid,
      'name': 'Tester',
      'legendPlayed': 'Axle',
      'gameMode': 'BATTLE_ROYALE',
      'gameLengthSecs': 600,
      'gameStartTimestamp': start,
      'gameEndTimestamp': 1782090600,
      'gameData': <dynamic>[],
      'BRScoreChange': 10,
      'BRScore': 1000,
      'BRRankImg': 'https://x/diamond4.png',
      'isPartyFull': false,
      'map': 'olympus_rotation',
    };

    test('rows that all fail to parse raise instead of reading as an empty '
        'history', () async {
      // Unreadable rows must not be recorded as a successful sync.
      stubResponse(
        status: 200,
        data: [
          row('uid123', start: 'not-a-number'),
          row('uid123', start: []),
        ],
      );

      expect(
        () => service.getMatches('uid123'),
        throwsA(isA<MalformedResponseException>()),
      );
    });

    test('rows that all belong to another uid raise too', () async {
      stubResponse(status: 200, data: [row('someone-else')]);

      expect(
        () => service.getMatches('uid123'),
        throwsA(isA<MalformedResponseException>()),
      );
    });

    test('one readable row among unreadable ones is still a result', () async {
      stubResponse(
        status: 200,
        data: [
          row('uid123', start: 'bad'),
          row('uid123'),
        ],
      );

      final result = await service.getMatches('uid123');

      expect((result as GamesMatches).matches, hasLength(1));
    });

    test('a 200 carrying a map raises instead of reading as pending', () async {
      // Without this the map would fall through to the 202 branch and report
      // "queued" forever, since no retry hint would ever clear it.
      stubResponse(status: 200, data: {'unexpected': 'shape'});

      expect(() => service.getMatches('uid123'), throwsA(isA<AppException>()));
    });
  });

  group('the read-only /games views stay on the primary server', () {
    late MockApiService mockApi;
    late GamesService service;

    setUp(() {
      mockApi = MockApiService();
      service = GamesService(mockApi);
    });

    // Tracking state and the hourly budget live on each server separately, so
    // the backup answers "not seen yet" for a profile the primary is tracking.
    test('eligibility is asked of the primary only', () async {
      when(
        () => mockApi.getWithStatus(
          ApiConstants.gamesEligibilityPath,
          params: any(named: 'params'),
          failover: false,
        ),
      ).thenAnswer((_) async => (status: 200, data: {'eligible': true}));

      final result = await service.getEligibility('uid123');

      expect(result.eligible, isTrue);
      verify(
        () => mockApi.getWithStatus(
          ApiConstants.gamesEligibilityPath,
          params: any(named: 'params'),
          failover: false,
        ),
      ).called(1);
    });

    test('capacity is asked of the primary only', () async {
      when(
        () => mockApi.getWithStatus(
          ApiConstants.gamesCapacityPath,
          failover: false,
        ),
      ).thenAnswer((_) async => (status: 200, data: {'free': 3}));

      final result = await service.getCapacity();

      expect(result?.free, 3);
      verify(
        () => mockApi.getWithStatus(
          ApiConstants.gamesCapacityPath,
          failover: false,
        ),
      ).called(1);
    });
  });
}
