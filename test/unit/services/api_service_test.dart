import 'dart:async';
import 'dart:typed_data';

import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/services/games_service.dart';
import 'package:apexlytics/utils/error_messages.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Replaces the transport only, so requests still run through ApiService's
/// real interceptors and error handling.
class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) onFetch;
  _FakeAdapter(this.onFetch);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => onFetch(options);

  @override
  void close({bool force = false}) {}
}

/// Holds every response until [gate] completes, so a test can act mid-request.
class _GatedAdapter implements HttpClientAdapter {
  final Future<void> gate;
  final ResponseBody Function(RequestOptions options) onFetch;
  _GatedAdapter(this.gate, this.onFetch);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await gate;
    return onFetch(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, String body, {Map<String, String>? headers}) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        for (final e in (headers ?? const {}).entries) e.key: [e.value],
      },
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  var dbCounter = 0;
  ApiService apiReturning(ResponseBody Function(RequestOptions) onFetch) =>
      ApiService(
        ApiCacheStore(
          overridePath:
              'file:api_service_test_${dbCounter++}?mode=memory&cache=shared',
        ),
        httpClientAdapter: _FakeAdapter(onFetch),
      );

  test('a response that lands after the cache was cleared is not cached', () async {
    final release = Completer<void>();
    final api = ApiService(
      ApiCacheStore(
        overridePath:
            'file:api_service_test_${dbCounter++}?mode=memory&cache=shared',
      ),
      httpClientAdapter: _GatedAdapter(
        release.future,
        (_) => _json(200, '{"name":"Someone"}'),
      ),
    );

    final request = api.get('/player/uid', params: {'uid': '1'});
    await Future<void>.delayed(Duration.zero); // the request is now in flight
    await api.clearCache(); // "Clear all data"
    release.complete();
    final result = await request;

    expect(result.data['name'], 'Someone', reason: 'the caller still gets it');
    expect(api.loadCached('/player/uid', params: {'uid': '1'}), isNull);
  });

  group('falling back to the stale cached copy', () {
    // One ApiService: 200 first (filling the cache), then whatever [next] says.
    Future<ApiService> primed(ResponseBody Function() next) async {
      var first = true;
      final api = apiReturning((_) {
        if (first) {
          first = false;
          return _json(200, '{"name":"OldName"}');
        }
        return next();
      });
      await api.get('/player', params: {'player': 'x'});
      return api;
    }

    for (final status in [401, 403, 404, 410]) {
      test('a $status is thrown with its status, not hidden behind the cache', () async {
        final api = await primed(() => _json(status, '{"error":"nope"}'));

        await expectLater(
          api.get('/player', params: {'player': 'x'}),
          throwsA(
            isA<AppException>().having((e) => e.status, 'status', status),
          ),
        );
      });
    }

    for (final status in [400, 429]) {
      test('a $status still serves the cached copy, marked stale', () async {
        final api = await primed(() => _json(status, '{"error":"later"}'));

        final result = await api.get('/player', params: {'player': 'x'});

        expect(result.data['name'], 'OldName');
        expect(result.staleAt, isNotNull);
      });
    }

    test('no answer at all (offline) still serves the cached copy', () async {
      var first = true;
      final api = apiReturning((options) {
        if (first) {
          first = false;
          return _json(200, '{"name":"OldName"}');
        }
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        );
      });
      await api.get('/player', params: {'player': 'x'});

      final result = await api.get('/player', params: {'player': 'x'});

      expect(result.data['name'], 'OldName');
      expect(result.staleAt, isNotNull);
    });

    test('a 404 with nothing cached is still the plain not-found error', () async {
      final api = apiReturning((_) => _json(404, '{"error":"Player not found"}'));

      await expectLater(
        api.get('/player', params: {'player': 'x'}),
        throwsA(isA<AppException>().having((e) => e.status, 'status', 404)),
      );
    });
  });

  group('getWithStatus carries the status of a real error response', () {
    // Dio rejects every non-2xx before the body is looked at, so the status
    // used to be dropped — a rejected request looked like no connection.
    test('a 401 keeps its status', () async {
      final api = apiReturning(
        (_) => _json(401, '{"error":"unauthorized"}'),
      );

      await expectLater(
        api.getWithStatus('/games'),
        throwsA(
          isA<AppException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.retryAfter, 'retryAfter', isNull),
        ),
      );
    });

    test('a 429 keeps its status and the server\'s Retry-After', () async {
      final api = apiReturning(
        (_) => _json(
          429,
          '{"error":"Too many requests"}',
          headers: {'retry-after': '45'},
        ),
      );

      await expectLater(
        api.getWithStatus('/games'),
        throwsA(
          isA<AppException>()
              .having((e) => e.status, 'status', 429)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 45),
              ),
        ),
      );
    });

    test('the friendly message is unchanged', () async {
      final api = apiReturning((_) => _json(401, '{}'));

      await expectLater(
        api.getWithStatus('/games'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'Unauthorized. Check your proxy configuration.',
          ),
        ),
      );
    });
  });

  test('GamesService surfaces the status the sync provider branches on', () async {
    // rankedSyncProvider's requestError/429 handling is only reachable if
    // this carries a real status.
    final games = GamesService(
      apiReturning((_) => _json(403, '{"error":"forbidden"}')),
    );

    await expectLater(
      games.getMatches('1006838015507'),
      throwsA(isA<AppException>().having((e) => e.status, 'status', 403)),
    );
  });
}
