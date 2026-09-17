import 'dart:async';

import 'package:dio/dio.dart';

/// Runs [action] with a [CancelToken] that self-cancels after [deadline] —
/// bounding a whole logical request (every retry and failover
/// `RetryInterceptor` might chain onto it), not just one attempt.
///
/// Dio carries the same `CancelToken` across retries and failover, since
/// it's part of the `RequestOptions` the interceptor re-issues each attempt —
/// so one timer here bounds the whole chain without `RetryInterceptor`
/// needing to know about deadlines at all.
///
/// A request already mid-retry-backoff when [deadline] fires isn't
/// interrupted instantly: Dio only checks cancellation before dispatching
/// the next attempt, so the failure can land slightly after [deadline], never
/// unboundedly later.
Future<T> withOverallDeadline<T>(
  Duration deadline,
  Future<T> Function(CancelToken cancelToken) action,
) async {
  final cancelToken = CancelToken();
  final timer = Timer(deadline, () {
    if (!cancelToken.isCancelled) {
      cancelToken.cancel('Exceeded the overall request deadline ($deadline)');
    }
  });
  try {
    return await action(cancelToken);
  } finally {
    // Whether action succeeded, failed, or was itself cancelled — a timer
    // left running past this point would fire against a token nobody reads
    // anymore, harmless but pointless.
    timer.cancel();
  }
}
