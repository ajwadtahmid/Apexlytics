import 'package:sentry_flutter/sentry_flutter.dart';

/// Player UIDs are 10-20 digit numbers; nothing else the app reports is.
final _uidPattern = RegExp(r'\d{10,20}');

/// Longest a single scrubbed string may be. Real error messages fit easily;
/// anything longer is most likely carrying a payload.
const _maxLength = 300;

/// [text] with anything that could identify a player removed, for sending to
/// the crash reporter — `app_logger`'s "never log names or UIDs" rule can't
/// stop an error's own text from carrying them.
///
/// - Only the first line is kept — a [FormatException] prints an excerpt of
///   the text it failed to parse on the lines after it.
/// - A sqflite `DatabaseException` is cut before its ` sql '…' args […]`
///   tail, which quotes the bound arguments (a UID, a player name).
/// - Anything UID-shaped left over is masked, and the result capped at
///   [_maxLength].
String scrubForCrashReport(String text) {
  var s = text;
  final newline = s.indexOf('\n');
  if (newline >= 0) s = s.substring(0, newline);
  final sql = s.indexOf(" sql '");
  if (sql >= 0) s = s.substring(0, sql);
  s = s.replaceAll(_uidPattern, '<uid>');
  if (s.length > _maxLength) s = '${s.substring(0, _maxLength)}…';
  return s;
}

/// Sentry `beforeSend`: scrubs every free-text field of an outgoing event
/// that app or error text can reach — exception values, the message, and
/// the breadcrumb trail attached to it. Also drops the event's user, which the SDK
/// can fill with a per-install id.
SentryEvent scrubSentryEvent(SentryEvent event, Hint hint) {
  event.user = null;
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final value = exception.value;
    if (value != null) exception.value = scrubForCrashReport(value);
  }
  final message = event.message;
  if (message != null) {
    message.formatted = scrubForCrashReport(message.formatted);
  }
  for (final breadcrumb in event.breadcrumbs ?? const <Breadcrumb>[]) {
    _scrubBreadcrumb(breadcrumb);
  }
  return event;
}

/// Sentry `beforeBreadcrumb`: breadcrumbs from `log.w`/`log.e` carry the
/// logged error's text in both the message and `data`.
Breadcrumb? scrubSentryBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb != null) _scrubBreadcrumb(breadcrumb);
  return breadcrumb;
}

void _scrubBreadcrumb(Breadcrumb breadcrumb) {
  final message = breadcrumb.message;
  if (message != null) breadcrumb.message = scrubForCrashReport(message);
  final data = breadcrumb.data;
  if (data != null) {
    breadcrumb.data = {
      for (final entry in data.entries)
        entry.key: entry.value is String
            ? scrubForCrashReport(entry.value as String)
            : entry.value,
    };
  }
}
