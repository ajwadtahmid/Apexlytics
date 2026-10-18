import 'dart:collection';

import 'log_scrub.dart';

/// One recorded log line, already scrubbed (see [scrubForReport]).
class LogEntry {
  final DateTime time;

  /// `I`, `W` or `E` (`D` for debug lines, which only a debug build keeps).
  final String level;
  final String text;

  const LogEntry(this.time, this.level, this.text);
}

/// The most recent log lines of this run, kept in memory for bug reports.
/// Nothing is written to disk, and a restart starts it empty.
///
/// Lines are scrubbed as they are added, so a UID that slipped into a message
/// is never held here at all.
class LogBuffer {
  LogBuffer({this.capacity = 500, this.maxLineLength = 240});

  /// The buffer the app's logger fills.
  static final LogBuffer instance = LogBuffer();

  /// How many lines are kept; the oldest go first.
  final int capacity;

  /// Longer lines are cut, so one stack trace cannot crowd out the rest.
  final int maxLineLength;

  final Queue<LogEntry> _entries = Queue();

  /// The kept lines, oldest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(String level, String message, {Object? error, DateTime? time}) {
    var text = error == null ? message : '$message ($error)';
    text = scrubForReport(text.replaceAll(RegExp(r'\s*\n\s*'), ' ⏎ ').trim());
    if (text.length > maxLineLength) {
      text = '${text.substring(0, maxLineLength - 1)}…';
    }
    _entries.add(LogEntry(time ?? DateTime.now(), level, text));
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  void clear() => _entries.clear();
}
