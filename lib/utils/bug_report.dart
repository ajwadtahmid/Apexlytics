import 'package:intl/intl.dart';

import 'backup_reminder.dart' show backupAgeLabel;
import 'formatting/format.dart' show formatBytes, formatNumber, timeAgo;
import 'log_buffer.dart';
import 'log_scrub.dart';

/// Where a bug report is going.
enum BugReportChannel { github, email }

/// How long the whole link may be (encoded), per channel. GitHub refuses links
/// much past 8 000 characters, and Windows hands `mailto:` links to the mail
/// app through a call that stops at about 2 000. Mobile and Linux mail apps
/// take far more, but a very long link is slow to open in a draft, so it stops
/// at a size that still holds a good amount of log.
const kGithubUrlBudget = 7000;
const kEmailUrlBudget = 12000;
const kWindowsEmailUrlBudget = 1900;

const _githubBase =
    'https://github.com/ajwadtahmid/Apexlytics/issues/new?body=';
const _emailBase =
    'mailto:support@ajwadtahmid.com?subject=Apexlytics+Bug+Report&body=';

/// What the app knows about itself that helps with a bug report. Nothing here
/// names a player: profiles show as a count and their platforms.
class DiagnosticsFacts {
  final String locale;
  final Duration utcOffset;

  /// Whether the notification plugin started, and whether the OS lets
  /// notifications through (null when not asked).
  final bool notificationsInitialised;
  final bool? notificationsPermitted;

  /// The alerts that are on, as `Ranked 15 min`.
  final List<String> alertsOn;

  /// Whether background fetch is available (null where there is none), and how
  /// the last run went.
  final bool? backgroundAvailable;
  final ({bool ok, DateTime at})? lastBackground;

  final int profileCount;
  final List<String> platforms;
  final String defaultTab;
  final int statsRefreshMinutes;
  final bool keepScreenOn;

  final int? games;
  final int? historyBytes;
  final int? cachedResponses;
  final int? cacheBytes;
  final DateTime? lastBackup;

  const DiagnosticsFacts({
    required this.locale,
    required this.utcOffset,
    required this.notificationsInitialised,
    required this.notificationsPermitted,
    required this.alertsOn,
    required this.backgroundAvailable,
    required this.lastBackground,
    required this.profileCount,
    required this.platforms,
    required this.defaultTab,
    required this.statsRefreshMinutes,
    required this.keepScreenOn,
    this.games,
    this.historyBytes,
    this.cachedResponses,
    this.cacheBytes,
    this.lastBackup,
  });
}

String _yesNo(bool? v) => v == null ? 'unknown' : (v ? 'yes' : 'no');

String _offset(Duration d) {
  final sign = d.isNegative ? '-' : '+';
  final abs = d.abs();
  final h = abs.inHours.toString().padLeft(2, '0');
  final m = (abs.inMinutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$h:$m';
}

/// The diagnostics as lines, most useful first, so a tight budget cuts the
/// least useful ones.
List<String> diagnosticsLines(DiagnosticsFacts f, DateTime now) {
  final background = f.lastBackground;
  final lastRun = background == null
      ? 'never recorded'
      : '${background.ok ? 'ok' : 'failed'} ${timeAgo(background.at)}';
  final refresh = f.statsRefreshMinutes == 0
      ? 'manual'
      : '${f.statsRefreshMinutes} min';
  return [
    'Notifications: started ${_yesNo(f.notificationsInitialised)}, '
        'allowed ${_yesNo(f.notificationsPermitted)}',
    'Alerts on: ${f.alertsOn.isEmpty ? 'none' : f.alertsOn.join(', ')}',
    'Background refresh: available ${_yesNo(f.backgroundAvailable)}, '
        'last $lastRun',
    'Profiles: ${f.profileCount}'
        '${f.platforms.isEmpty ? '' : ' (${f.platforms.join(', ')})'}',
    if (f.games != null && f.historyBytes != null)
      'Match history: ${formatNumber(f.games!)} '
          '${f.games == 1 ? 'game' : 'games'}, '
          '${formatBytes(f.historyBytes!)}',
    if (f.cachedResponses != null && f.cacheBytes != null)
      'Cached responses: ${f.cachedResponses}, ${formatBytes(f.cacheBytes!)}',
    'Last backup: '
        '${f.lastBackup == null ? 'never' : backupAgeLabel(f.lastBackup!, now)}',
    'Settings: default tab ${f.defaultTab}, refresh $refresh, '
        'keep screen on ${_yesNo(f.keepScreenOn)}',
    'Locale: ${f.locale}, ${_offset(f.utcOffset)}',
  ];
}

/// A report ready to open.
class BugReport {
  final Uri uri;

  /// How many log lines went in, out of how many were kept.
  final int logLinesIncluded;
  final int logLinesAvailable;

  const BugReport(this.uri, this.logLinesIncluded, this.logLinesAvailable);
}

/// Builds the link for [channel]: the usual template, then the diagnostics, then
/// as many of the newest log lines as fit in [maxUrlLength] (encoded).
///
/// A link cannot carry a file, so this is how a report holds a log at all. The
/// diagnostics come ahead of the log, and the log keeps its newest lines.
///
/// Everything is passed through [scrubForReport] again here, with [names] (the
/// saved profiles and favorites), which the log buffer cannot know.
BugReport composeBugReport(
  BugReportChannel channel, {
  required String version,
  required String build,
  required String platform,
  required String osVersion,
  required List<String> diagnostics,
  required List<LogEntry> logs,
  Iterable<String> names = const [],
  int? maxUrlLength,
}) {
  final github = channel == BugReportChannel.github;
  final budget = maxUrlLength ?? (github ? kGithubUrlBudget : kEmailUrlBudget);
  final base = github ? _githubBase : _emailBase;
  int size(String s) => Uri.encodeComponent(s).length;

  final head = github
      ? '**Describe the bug**\n'
            '<!-- What happened? What did you expect? -->\n\n'
            '**Steps to reproduce**\n'
            '1. \n'
            '2. \n\n'
            '**Additional context**\n'
            '<!-- Screenshots, logs, etc. -->\n\n'
            '---\n\n'
            '**App version:** $version ($build)\n'
            '**Platform:** $platform\n'
            '**OS version:** $osVersion'
      : 'Describe the bug:\n'
            '(What happened? What did you expect?)\n\n'
            'Steps to reproduce:\n'
            '1. \n'
            '2. \n\n'
            'Additional context:\n'
            '(Screenshots, logs, etc.)\n\n'
            '---\n\n'
            'App version: $version ($build)\n'
            'Platform: $platform\n'
            'OS version: $osVersion';
  var remaining = budget - base.length - size(head);

  String section(String title, List<String> lines) => github
      ? '\n\n<details>\n<summary>$title</summary>\n\n```\n'
            '${lines.join('\n')}\n```\n\n</details>'
      : '\n\n$title:\n${lines.join('\n')}';

  // Diagnostics first, in order, while they fit.
  final diagLines = <String>[];
  var diagCost = size(section('Diagnostics', []));
  for (final line in diagnostics) {
    final scrubbed = scrubForReport(line, names: names);
    final cost = size('$scrubbed\n');
    if (remaining - diagCost - cost < 0) break;
    diagLines.add(scrubbed);
    diagCost += cost;
  }
  if (diagLines.isNotEmpty) remaining -= diagCost;

  // Then the log, newest first, until the budget is spent.
  final time = DateFormat('HH:mm:ss');
  final logLines = <String>[];
  var logCost = size(section('Recent log (latest 00000 of 00000 lines, newest last)', []));
  for (final entry in logs.reversed) {
    final line = scrubForReport(
      '${time.format(entry.time)} ${entry.level} ${entry.text}',
      names: names,
    );
    final cost = size('$line\n');
    if (remaining - logCost - cost < 0) break;
    logLines.add(line);
    logCost += cost;
  }
  final shown = logLines.reversed.toList();

  final body = StringBuffer(head);
  if (diagLines.isNotEmpty) body.write(section('Diagnostics', diagLines));
  if (shown.isNotEmpty) {
    final title = shown.length == logs.length
        ? 'Recent log (${shown.length} lines, newest last)'
        : 'Recent log (latest ${shown.length} of ${logs.length} lines, '
              'newest last)';
    body.write(section(title, shown));
  }
  return BugReport(
    Uri.parse('$base${Uri.encodeComponent(body.toString())}'),
    shown.length,
    logs.length,
  );
}
