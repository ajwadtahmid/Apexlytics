import 'dart:io' show FileSystemException;

import 'package:dio/dio.dart';
import 'app_logger.dart';

class AppException implements Exception {
  final String message;

  /// The HTTP status this exception represents, when known — set by
  /// [ApiService.getWithStatus] for any response the server actually sent, so
  /// a caller can tell a real 4xx/5xx apart from a transport failure with no
  /// status at all. Null everywhere else.
  final int? status;

  /// The server's `Retry-After` in seconds, when it sent one (typically a
  /// 429 from the proxy's rate limits). Null otherwise.
  final Duration? retryAfter;

  const AppException(this.message, {this.status, this.retryAfter});

  @override
  String toString() => message;
}

/// A message for a failed file write or read that says what to do about it.
/// Keyed on the OS error code, and never includes the path (it can carry the
/// user's name). Codes are POSIX (`EPERM` 1, `EACCES` 13, `ENOSPC` 28, `EROFS`
/// 30) and the Windows equivalents (`ERROR_ACCESS_DENIED` 5,
/// `ERROR_DISK_FULL` 112, `ERROR_WRITE_PROTECT` 19).
String _fileSystemMessage(FileSystemException error) {
  return switch (error.osError?.errorCode) {
    1 || 13 || 5 || 30 || 19 =>
      "Couldn't write there — the app doesn't have permission for that "
          'location. Try a different one.',
    28 || 112 => 'Not enough storage space. Free some up and try again.',
    _ => "Couldn't read or write the file. Try a different location.",
  };
}

/// The server answered, but not with anything this client can read (a `200`
/// whose body isn't the expected shape — a captive portal, a proxy's error
/// page). Distinct from a connectivity failure: retrying on the short offline
/// interval would fail the same way, and it is worth reporting.
class MalformedResponseException extends AppException {
  const MalformedResponseException(super.message);
}

String friendlyError(Object? error) {
  if (error is AppException) return error.message;
  if (error is FileSystemException) return _fileSystemMessage(error);
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout =>
        'Request timed out. The server may be waking up — try again in a moment.',
      DioExceptionType.connectionError =>
        'No connection. Check your internet and try again.',
      // Only ApiService's own overall-deadline timer cancels a request today
      // (see utils/api_deadline.dart) — a real network timeout surfaces as
      // connectionTimeout/receiveTimeout above instead, so this is always the
      // "every retry and failover combined still took too long" case.
      DioExceptionType.cancel =>
        'Request took too long. Try again in a moment.',
      _ => switch (error.response?.statusCode) {
        400 => 'Bad request. Try again in a few minutes.',
        401 => 'Unauthorized. Check your proxy configuration.',
        403 => 'Access denied.',
        404 => 'Player not found. Check the name and platform.',
        410 => 'Unknown platform. Use PC, PS4, X1, or SWITCH.',
        429 => 'Rate limit reached. Wait a moment and try again.',
        500 => 'Server error. Try again later.',
        502 || 503 => 'Service unavailable. The proxy or Apex API may be down.',
        _ => 'Network error (${error.response?.statusCode ?? "unknown"}).',
      },
    };
  }
  if (error == null) return 'Unknown error';
  // Unrecognized error shape. Never show its toString(); log only the type, since the
  // text can carry paths or query data.
  log.w('Unhandled error type in friendlyError (${error.runtimeType})');
  return 'Something went wrong. Please try again.';
}
