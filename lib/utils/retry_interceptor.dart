import 'dart:math';

import 'package:dio/dio.dart';

import 'app_logger.dart';

const _kRetryKey = '_retry_count';
const _kUsedBackupKey = '_used_backup';

/// Retries requests on transient server errors (5xx) and network failures.
///
/// Uses exponential backoff — delays are [initialDelay] * 2^attempt:
///   attempt 0 → wait 1s, attempt 1 → wait 2s  (for default maxRetries=2)
///
/// The retry count is stored in [RequestOptions.extra] so it survives the
/// interceptor chain without any external state.
///
/// If [backupBaseUrl] is set and every retry against the primary host still
/// fails, the same request is reissued once against it (with its own fresh
/// retry budget) before giving up — this is what covers a primary host that's
/// asleep or down, e.g. a free-tier server that spins down.
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration initialDelay;
  final String? backupBaseUrl;

  /// How long a successful failover makes the backup the default host.
  final Duration primaryDownFor;

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 2,
    this.initialDelay = const Duration(seconds: 1),
    this.backupBaseUrl,
    this.primaryDownFor = const Duration(minutes: 5),
  });

  /// When set and in the future, requests start at [backupBaseUrl] instead of
  /// re-discovering the outage from scratch on every request.
  DateTime? _primaryDownUntil;

  bool get _primaryIsDown {
    final until = _primaryDownUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    // Window elapsed - forget it, so the primary coming back is noticed on the
    // next request rather than after a restart.
    _primaryDownUntil = null;
    return false;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final backup = backupBaseUrl;
    if (backup != null && backup.isNotEmpty && _primaryIsDown) {
      options
        ..baseUrl = backup
        // Marked as already-failed-over so onError doesn't try the backup a
        // second time and instead surfaces the error.
        ..extra[_kUsedBackupKey] = true;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // A primary that answers is a primary that is back; clear the shortcut
    // immediately rather than waiting out the window.
    if (_primaryDownUntil != null &&
        response.requestOptions.extra[_kUsedBackupKey] != true) {
      _primaryDownUntil = null;
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldRetry(err)) {
      return handler.next(err);
    }

    final attempt = (err.requestOptions.extra[_kRetryKey] as int?) ?? 0;

    if (attempt < maxRetries) {
      // Exponential backoff with max ceiling of maxRetries. Attempt counter tracked in
      // RequestOptions.extra[_kRetryKey] so it persists across the interceptor chain.
      final delay = initialDelay * pow(2, attempt).toInt();
      log.w(
        'Retry ${attempt + 1}/$maxRetries for ${err.requestOptions.path} '
        'in ${delay.inMilliseconds}ms '
        '(${err.response?.statusCode ?? err.type.name})',
      );

      await Future.delayed(delay);

      err.requestOptions.extra[_kRetryKey] = attempt + 1;
      return _refetch(err, handler);
    }

    // Retries against the current host are exhausted. Fail over to the
    // backup host exactly once — its own retries are tracked separately so
    // it gets the same retry budget the primary just used, and the
    // [_kUsedBackupKey] flag stops this from ever bouncing back and forth.
    final usedBackup = err.requestOptions.extra[_kUsedBackupKey] == true;
    final backup = backupBaseUrl;
    if (!usedBackup && backup != null && backup.isNotEmpty) {
      log.w(
        'Primary proxy failed after $maxRetries retries, trying backup '
        'for ${err.requestOptions.path}',
      );
      err.requestOptions
        ..baseUrl = backup
        ..extra[_kUsedBackupKey] = true
        ..extra[_kRetryKey] = 0;
      // Remember across requests, so the next one starts at the backup.
      _primaryDownUntil = DateTime.now().add(primaryDownFor);
      return _refetch(err, handler);
    }

    return handler.next(err);
  }

  Future<void> _refetch(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final response = await dio.fetch(err.requestOptions);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  bool _shouldRetry(DioException err) {
    final status = err.response?.statusCode;
    if (status != null && status >= 500) return true;
    // connectionTimeout, not connectionError, is what a sleeping free-tier
    // host produces (accepts the socket, then stalls).
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout;
  }
}
