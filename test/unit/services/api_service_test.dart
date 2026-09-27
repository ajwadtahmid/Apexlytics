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
