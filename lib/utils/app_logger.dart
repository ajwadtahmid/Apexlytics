import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// App-wide logger. Import and use directly:
///   log.d('cache hit');        // debug build only — never reaches production
///   log.i('service ready');    // release: low-priority Sentry breadcrumb
///   log.w('retry', error: e);  // release: warning Sentry breadcrumb
///   log.e('fatal', error: e, stackTrace: st); // release: Sentry exception + breadcrumb
///
/// Privacy rule: never pass player names, UIDs, or raw API query strings to
/// any log call — log counts, durations, status codes, and booleans only.
final log = Logger(
  printer: kDebugMode
      ? PrettyPrinter(
          methodCount: 2,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        )
      : SimplePrinter(colors: false),
  filter: kDebugMode ? DevelopmentFilter() : _ReleaseFilter(),
  output: kDebugMode ? ConsoleOutput() : _SentryOutput(),
);

/// Passes info+ in release. Debug logs are suppressed — they are too noisy
/// and contain internal state that should never leave the device.
class _ReleaseFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => event.level >= Level.info;
}

/// Routes log events to Sentry in release mode:
///   info    → low-priority breadcrumb (service lifecycle, useful for crash context)
///   warning → warning breadcrumb (recoverable errors, retry events)
///   error+  → Sentry exception capture + error breadcrumb (appears in its own trail)
///
/// The DSN guard in main.dart ensures all Sentry calls are no-ops when the
/// DSN is not configured (e.g. local dev without env vars).
class _SentryOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    final message = event.lines.join('\n');
    final timestamp = DateTime.now();
    final errorData = event.origin.error != null
        ? {'error': event.origin.error.toString()}
        : null;

    if (event.level >= Level.error) {
      Sentry.captureException(
        event.origin.error ?? message,
        stackTrace: event.origin.stackTrace,
      );
      // Add as a breadcrumb too so it appears in the trail on related events.
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          level: SentryLevel.error,
          category: 'app.log',
          timestamp: timestamp,
          data: errorData,
        ),
      );
    } else if (event.level >= Level.warning) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          level: SentryLevel.warning,
          category: 'app.log',
          timestamp: timestamp,
          data: errorData,
        ),
      );
    } else {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          level: SentryLevel.info,
          category: 'app.log',
          timestamp: timestamp,
        ),
      );
    }
  }
}
