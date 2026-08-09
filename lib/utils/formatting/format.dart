import 'package:intl/intl.dart';
import 'season_utils.dart' show SplitContext;

final _rpFormat = NumberFormat('#,###');

/// Formats an integer with comma-separated thousands (e.g., 1000 → '1,000').
String formatNumber(int number) => _rpFormat.format(number);

/// Returns a relative time string (e.g., '2h ago', '5m ago') based on elapsed time.
String timeAgo(DateTime timestamp) {
  final elapsed = DateTime.now().difference(timestamp);
  if (elapsed.isNegative) return 'just now';
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}

/// Capitalizes the first character of a string (e.g., 'apex' → 'Apex').
String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

/// One-line split orientation: 'Week 2 of 6 · Split ends in ~36 days'.
///
/// Days truncate (the final day reads '~0 days'); below a day the unit steps
/// to hours, then minutes. Null [ctx] yields an empty string.
String splitContextLabel(SplitContext? ctx) {
  if (ctx == null) return '';
  final week = 'Week ${ctx.week} of ${ctx.totalWeeks}';
  if (ctx.ended) return '$week · Split ended';

  final r = ctx.remaining;
  final String left;
  if (r.inDays >= 1) {
    left = '${r.inDays} ${r.inDays == 1 ? 'day' : 'days'}';
  } else if (r.inHours >= 1) {
    left = '${r.inHours} ${r.inHours == 1 ? 'hour' : 'hours'}';
  } else {
    final mins = r.inMinutes < 1 ? 1 : r.inMinutes;
    left = '$mins ${mins == 1 ? 'minute' : 'minutes'}';
  }
  return '$week · Split ends in ~$left';
}

/// Formats a duration in seconds into a compact label, scaling the unit so big
/// totals stay readable: 90061 → '1d 1h', 30600 → '8h 30m', 510 → '8m'.
String formatDuration(int seconds) {
  if (seconds <= 0) return '0m';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final mins = (seconds % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${mins}m';
  return '${mins}m';
}
