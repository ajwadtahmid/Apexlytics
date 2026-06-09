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

  group('PlayerService.nameToUid', () {
    test('throws when API returns empty UID', () async {
      when(
        () => mockApi.get(
          '/nametouid',
          params: any(named: 'params'),
          noCache: any(named: 'noCache'),
        ),
      ).thenAnswer(
        (_) async => const ApiResult({'uid': '', 'name': 'Unknown', 'avatar': ''}),
      );

      expect(
        () => service.nameToUid('SomePlayer', 'PC'),
        throwsA(
          isA<AppException>().having(
            (e) => e.toString(),
            'message',
            contains('Player not found'),
          ),
        ),
      );
    });

    test('returns result when API returns valid UID', () async {
      when(
        () => mockApi.get(
          '/nametouid',
          params: any(named: 'params'),
          noCache: any(named: 'noCache'),
        ),
      ).thenAnswer(
        (_) async =>
            const ApiResult({'uid': '12345', 'name': 'SomePlayer', 'avatar': ''}),
      );

      final result = await service.nameToUid('SomePlayer', 'PC');
      expect(result.uid, '12345');
      expect(result.name, 'SomePlayer');
    });

    test('passes player name and platform as query params', () async {
      when(
        () => mockApi.get(
          '/nametouid',
          params: any(named: 'params'),
          noCache: any(named: 'noCache'),
        ),
      ).thenAnswer(
        (_) async => const ApiResult({'uid': '99', 'name': 'x', 'avatar': ''}),
      );

      await service.nameToUid('TestName', 'X1');

      final captured = verify(
        () => mockApi.get(
          '/nametouid',
          params: captureAny(named: 'params'),
          noCache: true,
        ),
      ).captured;

      final params = captured.single as Map<String, dynamic>;
      expect(params['player'], 'TestName');
      expect(params['platform'], 'X1');
    });
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

      expect(
        () => service.getPlayerStatsByUid('42', 'PC'),
        throwsException,
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
        () => mockApi.get(
          '/player',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) async => ApiResult(fakeStatsJson));

      final result = await service.getPlayerStats('Player2', 'PS4');
      expect(result.data.name, 'Player2');
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
        () => mockApi.loadCached(
          any(),
          params: any(named: 'params'),
        ),
      ).thenReturn(null);

      final result = service.getCachedStats('Player', 'PC');
      expect(result, isNull);
    });

    test('returns cached stats when available', () {
      when(
        () => mockApi.loadCached(
          '/player',
          params: any(named: 'params'),
        ),
      ).thenReturn(ApiResult(fakeStatsJson));

      final result = service.getCachedStats('CachedPlayer', 'PC');
      expect(result, isNotNull);
      expect(result?.data.name, 'CachedPlayer');
    });

    test('uses UID endpoint when searchByUid is true', () {
      when(
        () => mockApi.loadCached(
          '/player/uid',
          params: any(named: 'params'),
        ),
      ).thenReturn(ApiResult(fakeStatsJson));

      service.getCachedStats('111', 'PC', searchByUid: true);

      verify(
        () => mockApi.loadCached(
          '/player/uid',
          params: any(named: 'params'),
        ),
      ).called(1);
    });
  });
}
