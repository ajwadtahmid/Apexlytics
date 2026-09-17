import 'dart:math';

import 'package:dio/dio.dart';

import 'app_logger.dart';

const _kRetryKey = '_retry_count';
const _kUsedBackupKey = '_used_backup';
// Set when a request starts on the backup because of the sticky window, not
// a real mid-request failover ([_kUsedBackupKey]). Lets a backup failure
// during the window fall back to the primary instead of hard-failing for
// the rest of [primaryDownFor].
const _kPreferredBackupKey = '_preferred_backup';

/// Retries requests on transient server errors (5xx) and network failures.
///
/// Uses exponential backoff — delays are [initialDelay] * 2^attempt:
///   attempt 0 → wait 1s  (for default maxRetries=1)
///
/// The retry count is stored in [RequestOptions.extra] so it survives the
/// interceptor chain without any external state.
///
/// If [backupBaseUrl] is set and every retry against the primary host still
/// fails, the same request is reissued once against it (with its own fresh
/// retry budget) before giving up — this is what covers a primary host that's
/// asleep or down, e.g. a free-tier server that spins down.
///
/// [maxRetries] defaults to 1 (2 attempts per host) rather than 2, keeping the
/// worst case for one logical request — every attempt against both the
/// primary and the backup timing out — at roughly two minutes instead of
/// three. The sticky [primaryDownFor] window already prevents re-paying this
/// full budget on every request during a sustained outage, so the ladder
/// itself only needs to be just long enough to ride out one transient blip.
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration initialDelay;
  final String? backupBaseUrl;

  /// How long a successful failover makes the backup the default host.
  final Duration primaryDownFor;

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 1,
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
        // A preference, not [_kUsedBackupKey]'s commitment: lets a backup
        // failure for this request still fall back to the primary in onError.
        ..extra[_kPreferredBackupKey] = true;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // A primary that answers is a primary that is back; clear the shortcut
    // immediately. A response served by the backup, failover or preference,
    // must not clear it.
    final extra = response.requestOptions.extra;
    final servedByBackup =
        extra[_kUsedBackupKey] == true || extra[_kPreferredBackupKey] == true;
    if (_primaryDownUntil != null && !servedByBackup) {
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

    // Retries against the current host are exhausted.
    final usedBackup = err.requestOptions.extra[_kUsedBackupKey] == true;
    final preferredBackup =
        err.requestOptions.extra[_kPreferredBackupKey] == true;
    final backup = backupBaseUrl;

    // Started on the backup by preference, not a real failover, and the
    // backup failed too — fall back to the primary rather than staying stuck
    // for the rest of the window. A still-down primary re-fails over below.
    if (preferredBackup && !usedBackup) {
      log.w(
        'Backup proxy failed while preferred; falling back to primary '
        'for ${err.requestOptions.path}',
      );
      _primaryDownUntil = null;
      err.requestOptions
        ..baseUrl = dio.options.baseUrl
        ..extra[_kPreferredBackupKey] = false
        ..extra[_kRetryKey] = 0;
      return _refetch(err, handler);
    }

    // Fail over to the backup host exactly once — its own retries are
    // tracked separately so it gets the same retry budget the primary just
    // used, and the [_kUsedBackupKey] flag stops this from ever bouncing
    // back and forth.
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
