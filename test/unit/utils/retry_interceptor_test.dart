import 'dart:typed_data';

import 'package:apexlytics/constants/timeout_constants.dart';
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

  test('a primary timeout fails straight over to the backup', () async {
    // A spun-down free-tier host produces connectionTimeout, not
    // connectionError - treating it as non-retryable skipped the failover.
    // And no same-host retry first: a second full timeout there used up the
    // overall deadline before the backup was ever tried.
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
    expect(calledBaseUrls, [primary, backup]);
  });

  test('every timeout type skips the same-host retry when a backup is '
      'available', () async {
    for (final type in const [
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ]) {
      final calledBaseUrls = <String>[];
      final dio = buildDio(
        maxRetries: 1,
        backupBaseUrl: backup,
        onFetch: (o) async {
          calledBaseUrls.add(o.baseUrl);
          if (o.baseUrl == backup) return _status(200);
          throw DioException(type: type, requestOptions: o);
        },
      );

      await dio.get('/player');
      expect(calledBaseUrls, [primary, backup], reason: '$type');
    }
  });

  test('a backup that times out still gets its retry, since there is no '
      'host left after it', () async {
    // The retry is what catches a sleeping backup once it has woken up.
    final calledBaseUrls = <String>[];
    var backupCalls = 0;
    final dio = buildDio(
      maxRetries: 1,
      backupBaseUrl: backup,
      onFetch: (o) async {
        calledBaseUrls.add(o.baseUrl);
        if (o.baseUrl == backup && ++backupCalls > 1) return _status(200);
        throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 15),
          requestOptions: o,
        );
      },
    );

    final response = await dio.get('/player');

    expect(response.statusCode, 200);
    expect(calledBaseUrls, [primary, backup, backup]);
  });

  test('a preferred backup that times out falls back to the primary, which '
      'then keeps its own retry instead of bouncing back', () async {
    final calledBaseUrls = <String>[];
    var armed = false;
    final dio = buildDio(
      maxRetries: 1,
      backupBaseUrl: backup,
      onFetch: (o) async {
        calledBaseUrls.add(o.baseUrl);
        if (!armed) {
          // First request: primary down, backup serves - arms the window.
          if (o.baseUrl == backup) return _status(200);
          return _status(503);
        }
        throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 15),
          requestOptions: o,
        );
      },
    );

    await dio.get('/first');
    armed = true;
    calledBaseUrls.clear();

    await expectLater(dio.get('/second'), throwsA(isA<DioException>()));
    // Backup (preferred) once, then the primary with its retry — never a
    // second trip to the backup that already failed this request.
    expect(calledBaseUrls, [backup, primary, primary]);
  });

  test('the overall deadline covers the longest failover chain', () {
    // One timed-out primary attempt, then the backup's full ladder. A
    // shorter deadline cancels the request before the backup gets its
    // chance, which is how failover used to be cut off.
    final attempt = TimeoutConstants.apiConnect > TimeoutConstants.apiReceive
        ? TimeoutConstants.apiConnect
        : TimeoutConstants.apiReceive;
    final backupLadder =
        attempt * (TimeoutConstants.retriesPerHost + 1) +
        TimeoutConstants.retryDelay * TimeoutConstants.retriesPerHost;
    expect(
      TimeoutConstants.overallRequestDeadline,
      greaterThanOrEqualTo(attempt + backupLadder),
    );
  });

  test('the background fetch deadline fits inside the OS task budget', () {
    // iOS gives a background fetch ~30 s in all; a task it kills never
    // records its result, so the request must give up well before that.
    expect(
      TimeoutConstants.backgroundFetchDeadline,
      lessThan(const Duration(seconds: 30)),
    );
  });

  test('every transport failure type is retryable', () async {
    // Enumerated, not spot-checked - a new type silently missing this list
    // is exactly how the connectionTimeout gap went unnoticed before. No
    // backup here, so timeouts keep their same-host retries: the primary is
    // the only host there is.
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

  group('no-failover requests', () {
    test('a timeout is not retried and never reaches the backup', () async {
      final hosts = <String>[];
      final dio = buildDio(
        backupBaseUrl: backup,
        onFetch: (o) async {
          hosts.add(o.uri.host);
          throw DioException(
            requestOptions: o,
            type: DioExceptionType.receiveTimeout,
          );
        },
      );

      await expectLater(
        dio.get('/games', options: Options(extra: {kNoFailoverKey: true})),
        throwsA(isA<DioException>()),
      );
      expect(hosts, ['primary.test']);
    });

    test('a 5xx is never sent to the backup', () async {
      final hosts = <String>[];
      final dio = buildDio(
        maxRetries: 0,
        backupBaseUrl: backup,
        onFetch: (o) async {
          hosts.add(o.uri.host);
          return _status(503);
        },
      );

      await expectLater(
        dio.get('/games', options: Options(extra: {kNoFailoverKey: true})),
        throwsA(isA<DioException>()),
      );
      expect(hosts, ['primary.test']);
    });

    test('stays on the primary even while the sticky backup window is open',
        () async {
      final hosts = <String>[];
      final dio = buildDio(
        maxRetries: 0,
        backupBaseUrl: backup,
        onFetch: (o) async {
          hosts.add(o.uri.host);
          return o.uri.host == 'primary.test' && o.path == '/other'
              ? _status(503)
              : _status(200);
        },
      );
      // An ordinary request fails over, opening the sticky window.
      await dio.get('/other');
      hosts.clear();

      await dio.get('/games', options: Options(extra: {kNoFailoverKey: true}));
      expect(hosts, ['primary.test']);
    });
  });
}
