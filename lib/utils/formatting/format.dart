import 'package:intl/intl.dart';
import 'season_utils.dart' show SplitContext;

final _rpFormat = NumberFormat('#,###');
final _shortDate = DateFormat('MMM d');
final _shortDateTime = DateFormat('MMM d, h:mm a');
final _clock = DateFormat('h:mm a');

/// Formats an integer with comma-separated thousands (e.g., 1000 → '1,000').
String formatNumber(int number) => _rpFormat.format(number);

/// [t] in the device's time zone as `Mar 4`. Match and split times are UTC
/// instants, so the conversion lives here rather than at each call site.
String formatShortDate(DateTime t) => _shortDate.format(t.toLocal());

/// [formatShortDate] with the time: `Mar 4, 9:30 PM`.
String formatShortDateTime(DateTime t) => _shortDateTime.format(t.toLocal());

/// When a session ran, in the device's time zone. Within one day the date leads
/// and the times follow in brackets: `Oct 9 (11:12 AM – 3:34 PM)`. Across
/// midnight each end carries its own date: `Oct 9 11:59 PM to Oct 10 3:03 AM`.
String formatSessionSpan(DateTime start, DateTime end) {
  final s = start.toLocal(), e = end.toLocal();
  if (s.year == e.year && s.month == e.month && s.day == e.day) {
    return '${_shortDate.format(s)} (${_clock.format(s)} – ${_clock.format(e)})';
  }
  return '${_shortDate.format(s)} ${_clock.format(s)} to '
      '${_shortDate.format(e)} ${_clock.format(e)}';
}

/// Formats a delta-style number with an explicit '+' for non-negative values
/// (e.g. RP/game, a comparison delta) — negatives already carry their own '-'.
///
/// A value that rounds to zero reads as zero ('+0.0'), never as '-0.0' (a tiny
/// negative) or '+-0.0' (negative zero).
String formatSigned(double value) {
  final text = value.toStringAsFixed(1);
  if (text == '-0.0') return '+0.0';
  return value >= 0 ? '+$text' : text;
}

/// [formatSigned], for an already-integer delta (e.g. total RP).
String formatSignedInt(int value) =>
    '${value >= 0 ? '+' : ''}${formatNumber(value)}';

/// A ratio (0..1) as a percentage with [decimals] places: `0.3994` is `39.9%`.
/// One decimal by default, so a rate isn't rounded to a neighbouring whole
/// number (`39.94%` as `40%`).
String formatPercent(double ratio, {int decimals = 1}) =>
    '${(ratio * 100).toStringAsFixed(decimals)}%';

/// A count with its noun, pluralised: `plural(1, 'game')` is `1 game`,
/// `plural(3, 'game')` is `3 games`. [many] overrides the default `word + s`
/// for the plural form (`plural(2, 'ranked game', 'ranked games')`).
String plural(int n, String word, [String? many]) =>
    n == 1 ? '$n $word' : '$n ${many ?? '${word}s'}';

/// A storage size for people: `312 B`, `48 KB`, `3.2 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Shown where a stat has no reading at all (e.g. no game reported the kills
/// tracker), instead of a 0 that would read as a measured value.
const kNoReading = '—';

/// [n] with thousands grouping, or [kNoReading] when null.
String formatNumberOrNone(int? n) => n == null ? kNoReading : formatNumber(n);

/// An average kills figure to one decimal, or [kNoReading] when null.
String formatAvgKills(double? avg) =>
    avg == null ? kNoReading : avg.toStringAsFixed(1);

/// An average damage figure as a whole number, or [kNoReading] when null.
String formatAvgDamage(double? avg) =>
    avg == null ? kNoReading : formatNumber(avg.round());

/// A kills/damage [total], or [kNoReading] when none of the games it covers
/// ([reportedGames]) reported the tracker. A partial total (some games
/// reported) is shown as is.
String formatTotalOrNone(int total, int reportedGames) =>
    reportedGames == 0 ? kNoReading : formatNumber(total);

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
