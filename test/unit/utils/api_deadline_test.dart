import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/api_deadline.dart';

void main() {
  test('completes normally and returns the action\'s value', () async {
    final result = await withOverallDeadline(
      const Duration(milliseconds: 200),
      (token) async => 'ok',
    );
    expect(result, 'ok');
  });

  test('cancels the token once the deadline elapses', () async {
    final tokenCompleter = Completer<CancelToken>();
    final future = withOverallDeadline<void>(const Duration(milliseconds: 30), (
      cancelToken,
    ) async {
      tokenCompleter.complete(cancelToken);
      // Simulate a request that's still in flight (e.g. mid retry-backoff)
      // well past the deadline.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    final cancelToken = await tokenCompleter.future;
    await future;

    expect(cancelToken.isCancelled, isTrue);
  });

  test(
    'does not cancel the token once the action has already returned',
    () async {
      late CancelToken usedToken;
      await withOverallDeadline(const Duration(milliseconds: 20), (
        token,
      ) async {
        usedToken = token;
        return 'done';
      });

      // Give the deadline timer a chance to fire if it hadn't actually been
      // cancelled — this is what proves the `finally { timer.cancel(); }`
      // path actually runs.
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(usedToken.isCancelled, isFalse);
    },
  );

  test('propagates the action\'s own exception unchanged', () async {
    await expectLater(
      () => withOverallDeadline<void>(
        const Duration(milliseconds: 200),
        (token) async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
