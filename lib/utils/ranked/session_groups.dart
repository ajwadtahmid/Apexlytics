import 'package:intl/intl.dart';
import 'ranked_aggregates.dart';

/// Sessions that fall in the same stretch of time, under one heading.
class SessionGroup {
  /// "Today", "Yesterday", "This week", "Last week", or a month and year.
  final String label;

  /// Newest first, as they were given.
  final List<RankedSession> sessions;

  const SessionGroup(this.label, this.sessions);

  int get netRp => sessions.fold(0, (n, s) => n + s.netRp);
}

/// [sessions] (newest first) cut into runs under a heading for when they were
/// played, judged on the device's local date: Today, Yesterday, the rest of this
/// week (weeks start on Monday), last week, then a heading per month. [now]
/// stands in for the current time in tests.
List<SessionGroup> groupSessions(
  List<RankedSession> sessions, {
  DateTime? now,
}) {
  final today = _dayOf(now ?? DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));
  final thisWeek = today.subtract(Duration(days: today.weekday - 1));
  final lastWeek = thisWeek.subtract(const Duration(days: 7));
  final month = DateFormat('MMMM yyyy');

  String labelOf(DateTime start) {
    final day = _dayOf(start);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    if (!day.isBefore(thisWeek)) return 'This week';
    if (!day.isBefore(lastWeek)) return 'Last week';
    return month.format(day);
  }

  final groups = <SessionGroup>[];
  String? current;
  for (final s in sessions) {
    final label = labelOf(s.start.toLocal());
    if (label != current) {
      groups.add(SessionGroup(label, []));
      current = label;
    }
    groups.last.sessions.add(s);
  }
  return groups;
}

/// The calendar day of [t], without the time.
DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
