import 'dart:typed_data';

import 'package:apexlytics/utils/retry_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fakes the transport layer only, so requests still flow through the real
/// [Dio] pipeline (and therefore the real [RetryInterceptor]) rather than
/// mocking Dio's own internals, which the package deliberately doesn't
/// expose for testing (InterceptorState/InterceptorResultType are hidden
/// from the public API).
class _FakeAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) onFetch;
  _FakeAdapter(this.onFetch);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => onFetch(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _status(int code) =>
    ResponseBody.fromString('', code, headers: {});

void main() {
  const primary = 'https://primary.test';
  const backup = 'https://backup.test';

  Dio buildDio({
    required Future<ResponseBody> Function(RequestOptions) onFetch,
    int maxRetries = 2,
    String? backupBaseUrl,
    Duration primaryDownFor = const Duration(minutes: 5),
  }) {
    final dio = Dio(BaseOptions(baseUrl: primary));
    dio.httpClientAdapter = _FakeAdapter(onFetch);
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        maxRetries: maxRetries,
        initialDelay: Duration.zero,
        backupBaseUrl: backupBaseUrl,
        primaryDownFor: primaryDownFor,
      ),
    );
    return dio;
  }

  test('non-retryable errors (e.g. 404) are not retried at all', () async {
    var calls = 0;
    final dio = buildDio(
      onFetch: (o) async {
        calls++;
        return _status(404);
      },
    );

    await expectLater(dio.get('/player'), throwsA(isA<DioException>()));
    expect(calls, 1);
  });

  test(
    'retries the same host up to maxRetries, then gives up without a backup',
    () async {
      var calls = 0;
      final dio = buildDio(
        maxRetries: 2,
        onFetch: (o) async {
          calls++;
          return _status(503);
        },
      );

      await expectLater(dio.get('/player'), throwsA(isA<DioException>()));
      expect(calls, 3); // initial attempt + 2 retries
    },
  );

  test('fails over to the backup host once retries are exhausted', () async {
    final calledBaseUrls = <String>[];
    final dio = buildDio(
      maxRetries: 1,
      backupBaseUrl: backup,
      onFetch: (o) async {
        calledBaseUrls.add(o.baseUrl);
        return o.baseUrl == backup ? _status(200) : _status(503);
      },
    );

    final response = await dio.get('/player');

    expect(response.statusCode, 200);
    // Primary gets its full retry budget (2 calls) before the backup (1 call).
    expect(calledBaseUrls, [primary, primary, backup]);
  });

  test('a connection timeout retries and fails over to the backup', () async {
    // A spun-down free-tier host produces connectionTimeout, not
    // connectionError - treating it as non-retryable skipped the failover.
    final calledBaseUrls = <String>[];
    final dio = buildDio(
      maxRetries: 1,
      backupBaseUrl: backup,
      onFetch: (o) async {
        calledBaseUrls.add(o.baseUrl);
        if (o.baseUrl == backup) return _status(200);
        throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 15),
          requestOptions: o,
        );
      },
    );

    final response = await dio.get('/player');

    expect(response.statusCode, 200);
    expect(calledBaseUrls, [primary, primary, backup]);
  });

  test('every transport failure type is retryable', () async {
    // Enumerated, not spot-checked - a new type silently missing this list
    // is exactly how the connectionTimeout gap went unnoticed before.
    for (final type in const [
      DioExceptionType.connectionTimeout,
      DioExceptionType.connectionError,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ]) {
      var calls = 0;
      final dio = buildDio(
        maxRetries: 2,
        onFetch: (o) async {
          calls++;
          throw DioException(type: type, requestOptions: o);
        },
      );

      await expectLater(dio.get('/player'), throwsA(isA<DioException>()));
      expect(calls, 3, reason: '$type should retry (initial + 2)');
    }
  });

  test('a known-down primary is skipped on the next request', () async {
    // Failover state used to live only in one request's RequestOptions, so
    // every request re-discovered the outage from scratch.
    final calledBaseUrls = <String>[];
    final dio = buildDio(
      maxRetries: 1,
      backupBaseUrl: backup,
      onFetch: (o) async {
        calledBaseUrls.add(o.baseUrl);
        if (o.baseUrl == backup) return _status(200);
        throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 15),
          requestOptions: o,
        );
      },
    );

    await dio.get('/first');
    calledBaseUrls.clear();
    await dio.get('/second');

    // Straight to the backup - no primary attempts at all.
    expect(calledBaseUrls, [backup]);
  });

  test('a recovered primary clears the shortcut', () async {
    var primaryDown = true;
    final calledBaseUrls = <String>[];
    final dio = buildDio(
      maxRetries: 0,
      backupBaseUrl: backup,
      // A window short enough to elapse within the test.
      primaryDownFor: const Duration(milliseconds: 40),
      onFetch: (o) async {
        calledBaseUrls.add(o.baseUrl);
        if (o.baseUrl == backup) return _status(200);
        if (primaryDown) {
          throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 15),
            requestOptions: o,
          );
        }
        return _status(200);
      },
    );

    await dio.get('/first'); // primary fails, backup serves
    primaryDown = false;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    calledBaseUrls.clear();

    await dio.get('/second'); // window elapsed - primary retried and works
    expect(calledBaseUrls, [primary]);

    calledBaseUrls.clear();
    await dio.get('/third'); // and stays there
    expect(calledBaseUrls, [primary]);
  });

  test('never bounces back to primary if the backup also fails', () async {
    final calledBaseUrls = <String>[];
    final dio = buildDio(
      maxRetries: 0,
      backupBaseUrl: backup,
      onFetch: (o) async {
        calledBaseUrls.add(o.baseUrl);
        return _status(503);
      },
    );

    await expectLater(dio.get('/player'), throwsA(isA<DioException>()));
    // One attempt at the primary, one at the backup, then it gives up —
    // never a second round back at the primary.
    expect(calledBaseUrls, [primary, backup]);
  });

  test(
    'falls back to the primary when the backup fails during the sticky '
    'window',
    () async {
      // The sticky window is a preference, not a commitment - a request
      // routed to the backup purely because the window is active must still
      // be able to reach a now-healthy primary if the backup itself fails.
      final calledBaseUrls = <String>[];
      var primaryDown = true; // only true for the very first attempt below
      var backupDown = false;
      final dio = buildDio(
        maxRetries: 0,
        backupBaseUrl: backup,
        onFetch: (o) async {
          calledBaseUrls.add(o.baseUrl);
          if (o.baseUrl == backup) return backupDown ? _status(503) : _status(200);
          return primaryDown ? _status(503) : _status(200);
        },
      );

      // Arms the sticky window: primary fails once, backup serves it.
      await dio.get('/first');
      primaryDown = false; // the primary has since recovered...
      backupDown = true; // ...but the backup is what's flaky right now.
      calledBaseUrls.clear();

      // Routed straight to the backup by the sticky preference. The backup
      // fails, so this must fall back to the primary instead of hard-failing
      // for the rest of the window.
      final response = await dio.get('/second');

      expect(response.statusCode, 200);
      expect(calledBaseUrls, [backup, primary]);
    },
  );
}
