import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/services/player_service.dart';
import 'package:apexlytics/utils/error_messages.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  late MockApiService mockApi;
  late PlayerService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockApi = MockApiService();
    service = PlayerService(mockApi);
  });

  group('PlayerService.getPlayerStatsByUid', () {
    final fakeStatsJson = {
      'global': {
        'name': 'Player1',
        'uid': '42',
        'level': 100,
        'rank': {'rankName': 'Platinum', 'rankScore': 8000},
        'platform': 'PC',
      },
      'realtime': {'isOnline': 0, 'isInGame': 0},
      'legends': {
        'selected': {'LegendName': 'Wraith', 'data': []},
        'all': {},
      },
    };

    test('returns PlayerStats parsed from API response', () async {
      when(
        () => mockApi.get(
          '/player/uid',
          params: any(named: 'params'),
          noCache: any(named: 'noCache'),
        ),
      ).thenAnswer((_) async => ApiResult(fakeStatsJson));

      final result = await service.getPlayerStatsByUid('42', 'PC');
      expect(result.data.name, 'Player1');
      expect(result.data.rankScore, 8000);
    });

    test('throws when API returns null data', () async {
      when(
        () => mockApi.get(
          '/player/uid',
          params: any(named: 'params'),
          noCache: any(named: 'noCache'),
        ),
      ).thenThrow(Exception('Invalid response'));

      expect(() => service.getPlayerStatsByUid('42', 'PC'), throwsException);
    });

    void stubBody(Map<String, dynamic> body) {
      when(
        () => mockApi.get(
          '/player/uid',
          params: any(named: 'params'),
          noCache: any(named: 'noCache'),
        ),
      ).thenAnswer((_) async => ApiResult(body));
    }

    // Upstream answers an unknown player with a 200 `{"Error": ...}`.
    test('an Error body for an unknown player is a 404, never stats', () async {
      stubBody({'Error': 'Player not found'});

      await expectLater(
        service.getPlayerStatsByUid('42', 'PC'),
        throwsA(
          isA<AppException>()
              .having((e) => e.status, 'status', 404)
              .having((e) => e.message, 'message', contains('UID')),
        ),
      );
    });

    test('any other Error body is a failure with a retry message', () async {
      stubBody({'Error': 'Internal error, try again later'});

      await expectLater(
        service.getPlayerStatsByUid('42', 'PC'),
        throwsA(
          isA<AppException>().having((e) => e.status, 'status', isNull),
        ),
      );
    });

    test('a body with no player uid is not found, not an empty player', () async {
      stubBody({'something': 'else'});

      await expectLater(
        service.getPlayerStatsByUid('42', 'PC'),
        throwsA(
          isA<AppException>().having((e) => e.status, 'status', 404),
        ),
      );
    });
  });

  group('PlayerService.getPlayerStats', () {
    final fakeStatsJson = {
      'global': {
        'name': 'Player2',
        'uid': '99',
        'level': 50,
        'rank': {'rankName': 'Gold', 'rankScore': 4000},
        'platform': 'PS4',
      },
      'realtime': {'isOnline': 0, 'isInGame': 0},
      'legends': {
        'selected': {'LegendName': 'Octane', 'data': []},
        'all': {},
      },
    };

    test('returns PlayerStats when API succeeds', () async {
      when(
        () => mockApi.get('/player', params: any(named: 'params')),
      ).thenAnswer((_) async => ApiResult(fakeStatsJson));

      final result = await service.getPlayerStats('Player2', 'PS4');
      expect(result.data.name, 'Player2');
    });

    test('an Error body names the name, not the UID', () async {
      when(
        () => mockApi.get('/player', params: any(named: 'params')),
      ).thenAnswer((_) async => const ApiResult({'Error': 'Player not found'}));

      await expectLater(
        service.getPlayerStats('Nobody', 'PC'),
        throwsA(
          isA<AppException>()
              .having((e) => e.status, 'status', 404)
              .having((e) => e.message, 'message', contains('name')),
        ),
      );
    });
  });

  group('PlayerService.getCachedStats', () {
    final fakeStatsJson = {
      'global': {
        'name': 'CachedPlayer',
        'uid': '111',
        'level': 75,
        'rank': {'rankName': 'Diamond', 'rankScore': 10000},
        'platform': 'PC',
      },
      'realtime': {'isOnline': 0, 'isInGame': 0},
      'legends': {
        'selected': {'LegendName': 'Wraith', 'data': []},
        'all': {},
      },
    };

    test('returns null when no cache exists', () {
      when(
        () => mockApi.loadCached(any(), params: any(named: 'params')),
      ).thenReturn(null);

      final result = service.getCachedStats('Player', 'PC');
      expect(result, isNull);
    });

    test('returns cached stats when available', () {
      when(
        () => mockApi.loadCached('/player', params: any(named: 'params')),
      ).thenReturn(ApiResult(fakeStatsJson));

      final result = service.getCachedStats('CachedPlayer', 'PC');
      expect(result, isNotNull);
      expect(result?.data.name, 'CachedPlayer');
    });

    test('a cached body that fails to parse reads as a miss, so the caller '
        'reaches the network instead of rebuilding from it', () {
      // A tracker entry that isn't an object throws in debug builds.
      final unreadable = {
        ...fakeStatsJson,
        'legends': {
          'selected': {
            'LegendName': 'Wraith',
            'data': [5],
          },
          'all': {},
        },
      };
      when(
        () => mockApi.loadCached('/player/uid', params: any(named: 'params')),
      ).thenReturn(ApiResult(unreadable));

      expect(
        service.getCachedStats('111', 'PC', searchByUid: true),
        isNull,
      );
    });

    test('uses UID endpoint when searchByUid is true', () {
      when(
        () => mockApi.loadCached('/player/uid', params: any(named: 'params')),
      ).thenReturn(ApiResult(fakeStatsJson));

      service.getCachedStats('111', 'PC', searchByUid: true);

      verify(
        () => mockApi.loadCached('/player/uid', params: any(named: 'params')),
      ).called(1);
    });
  });
}
