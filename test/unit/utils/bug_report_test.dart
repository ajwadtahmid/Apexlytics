import 'package:apexlytics/utils/bug_report.dart';
import 'package:apexlytics/utils/log_buffer.dart';
import 'package:apexlytics/utils/log_scrub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scrubForReport', () {
    test('hides UIDs, whatever surrounds them', () {
      expect(
        scrubForReport('lookup 1006838015507 failed, uid:1006838015507.'),
        'lookup <uid> failed, uid:<uid>.',
      );
    });

    test('leaves short numbers alone', () {
      expect(
        scrubForReport('3 retries, status 429, 1200 ms'),
        '3 retries, status 429, 1200 ms',
      );
    });

    test('hides the value of a query parameter that names someone', () {
      expect(
        scrubForReport('GET /bridge?player=Aceu&platform=PC&auth=abc123'),
        'GET /bridge?player=<redacted>&platform=PC&auth=<redacted>',
      );
      expect(
        scrubForReport('https://x.test/a?uid=555&name=Some%20One'),
        'https://x.test/a?uid=<redacted>&name=<redacted>',
      );
    });

    test('hides saved names, ignoring case, but not tiny ones', () {
      expect(
        scrubForReport(
          'searched ACEU then aceu again, and Mr Torgue',
          names: ['Aceu', 'Mr Torgue', 'Bo'],
        ),
        'searched <name> then <name> again, and <name>',
      );
      expect(scrubForReport('a Bo b', names: ['Bo']), 'a Bo b');
    });

    test('hides names that hold regex characters without breaking', () {
      expect(
        scrubForReport('hello [x]*.+ there', names: ['[x]*.+']),
        'hello <name> there',
      );
    });

    test('hides email addresses', () {
      expect(
        scrubForReport('sent to someone.name+tag@example.co.uk ok'),
        'sent to <email> ok',
      );
    });

    test('hides the account in a file path', () {
      expect(
        scrubForReport('open /home/ajwad/.local/share/app.db failed'),
        'open /home/<user>/.local/share/app.db failed',
      );
      expect(
        scrubForReport('open /Users/Sam/Library/x failed'),
        'open /Users/<user>/Library/x failed',
      );
      expect(
        scrubForReport(r'open C:\Users\Sam\AppData\x failed'),
        r'open C:\Users\<user>\AppData\x failed',
      );
    });
  });

  group('LogBuffer', () {
    test('keeps lines oldest first, and drops the oldest past capacity', () {
      final buffer = LogBuffer(capacity: 3);

      for (var i = 1; i <= 5; i++) {
        buffer.add('I', 'line $i');
      }

      expect([for (final e in buffer.entries) e.text], [
        'line 3',
        'line 4',
        'line 5',
      ]);
    });

    test('scrubs as it records, so a UID is never held', () {
      final buffer = LogBuffer();

      buffer.add('W', 'failed for 1006838015507', error: 'uid=1006838015507');

      final text = buffer.entries.single.text;
      expect(text, isNot(contains('1006838015507')));
      expect(text, contains('<uid>'));
      expect(text, contains('uid=<redacted>'));
    });

    test('puts a multi-line message on one line and cuts a long one', () {
      final buffer = LogBuffer(maxLineLength: 30);

      buffer.add('E', 'first\n  second\nthird');
      buffer.add('E', 'x' * 100);

      expect(buffer.entries[0].text, 'first ⏎ second ⏎ third');
      expect(buffer.entries[1].text.length, 30);
      expect(buffer.entries[1].text, endsWith('…'));
    });

    test('records the level and time given', () {
      final buffer = LogBuffer();
      final at = DateTime(2026, 10, 20, 9, 5, 7);

      buffer.add('W', 'hmm', time: at);

      expect(buffer.entries.single.level, 'W');
      expect(buffer.entries.single.time, at);
    });
  });

  group('diagnosticsLines', () {
    final now = DateTime(2026, 10, 20, 12);
    DiagnosticsFacts facts({
      List<String> alertsOn = const [],
      bool? permitted = true,
      ({bool ok, DateTime at})? lastBackground,
    }) => DiagnosticsFacts(
      locale: 'en_US',
      utcOffset: const Duration(hours: 5, minutes: 30),
      notificationsInitialised: true,
      notificationsPermitted: permitted,
      alertsOn: alertsOn,
      backgroundAvailable: true,
      lastBackground: lastBackground,
      profileCount: 2,
      platforms: const ['PC', 'PS4'],
      defaultTab: 'Home',
      statsRefreshMinutes: 10,
      keepScreenOn: false,
      games: 2333,
      historyBytes: 1258291,
      cachedResponses: 42,
      cacheBytes: 90000,
      lastBackup: now.subtract(const Duration(days: 12)),
    );

    test('says how notifications and background refresh stand', () {
      final lines = diagnosticsLines(
        facts(
          alertsOn: ['Ranked 15 min', 'Pubs 10 min'],
          lastBackground: (
            ok: false,
            at: DateTime.now().subtract(const Duration(hours: 3)),
          ),
        ),
        now,
      );

      expect(lines[0], 'Notifications: started yes, allowed yes');
      expect(lines[1], 'Alerts on: Ranked 15 min, Pubs 10 min');
      expect(lines[2], 'Background refresh: available yes, last failed 3h ago');
    });

    test('is honest about what is not known', () {
      final lines = diagnosticsLines(facts(permitted: null), now);

      expect(lines[0], 'Notifications: started yes, allowed unknown');
      expect(lines[1], 'Alerts on: none');
      expect(lines[2], contains('last never recorded'));
    });

    test('covers profiles, storage, backup, settings and locale', () {
      final text = diagnosticsLines(facts(), now).join('\n');

      expect(text, contains('Profiles: 2 (PC, PS4)'));
      expect(text, contains('Match history: 2,333 games, 1.2 MB'));
      expect(text, contains('Cached responses: 42, 88 KB'));
      expect(text, contains('Last backup: 12 days ago'));
      expect(text, contains('Settings: default tab Home, refresh 10 min'));
      expect(text, contains('Locale: en_US, UTC+05:30'));
    });

    test('names no player', () {
      final text = diagnosticsLines(facts(), now).join('\n');

      expect(text, isNot(contains('Aceu')));
      expect(text, isNot(matches(RegExp(r'\d{10,}'))));
    });
  });

  group('composeBugReport', () {
    final base = DateTime(2026, 10, 20, 9, 30);
    List<LogEntry> log(int n, {String text = 'something happened'}) => [
      for (var i = 0; i < n; i++)
        LogEntry(
          base.add(Duration(seconds: i)),
          i.isEven ? 'I' : 'W',
          '$text #$i',
        ),
    ];

    BugReport compose(
      BugReportChannel channel, {
      List<LogEntry>? logs,
      List<String> diagnostics = const ['Notifications: started yes'],
      Iterable<String> names = const [],
      int? maxUrlLength,
    }) => composeBugReport(
      channel,
      version: '1.4.0',
      build: '27',
      platform: 'android',
      osVersion: 'Android 14',
      diagnostics: diagnostics,
      logs: logs ?? log(5),
      names: names,
      maxUrlLength: maxUrlLength,
    );

    String body(BugReport r) => Uri.decodeComponent(
      r.uri.toString().substring(r.uri.toString().indexOf('body=') + 5),
    );

    test('GitHub: opens a new issue with the template, details and log', () {
      final r = compose(BugReportChannel.github);
      final text = body(r);

      expect(
        r.uri.toString(),
        startsWith(
          'https://github.com/ajwadtahmid/apexlytics/issues/new?body=',
        ),
      );
      expect(text, contains('**Describe the bug**'));
      expect(text, contains('**App version:** 1.4.0 (27)'));
      expect(text, contains('**Platform:** android'));
      expect(text, contains('<summary>Diagnostics</summary>'));
      expect(text, contains('Notifications: started yes'));
      expect(text, contains('<summary>Recent log (5 lines, newest last)'));
      expect(text, contains('09:30:00 I something happened #0'));
      expect(text, contains('09:30:04 I something happened #4'));
      expect(r.logLinesIncluded, 5);
      expect(r.logLinesAvailable, 5);
    });

    test('email: plain text to support, with the same content', () {
      final r = compose(BugReportChannel.email);
      final text = body(r);

      expect(
        r.uri.toString(),
        startsWith(
          'mailto:support@ajwadtahmid.com?subject=Apexlytics+Bug+Report&body=',
        ),
      );
      expect(text, contains('Describe the bug:'));
      expect(text, contains('App version: 1.4.0 (27)'));
      expect(text, contains('\n\nDiagnostics:\nNotifications: started yes'));
      expect(text, contains('Recent log (5 lines, newest last):'));
      expect(text, isNot(contains('<details>')));
    });

    test('lists the log oldest to newest', () {
      final text = body(compose(BugReportChannel.github));

      expect(
        text.indexOf('#0'),
        lessThan(text.indexOf('#4')),
        reason: 'newest last',
      );
    });

    for (final channel in BugReportChannel.values) {
      test('$channel: stays within its budget, however long the log', () {
        final r = compose(channel, logs: log(2000));
        final budget = channel == BugReportChannel.github
            ? kGithubUrlBudget
            : kEmailUrlBudget;

        expect(r.uri.toString().length, lessThanOrEqualTo(budget));
        expect(r.logLinesIncluded, lessThan(2000));
        // A good amount of it, not a handful.
        expect(r.logLinesIncluded, greaterThan(40));
      });

      test('$channel: keeps the newest lines and says it cut the rest', () {
        final r = compose(channel, logs: log(2000));
        final text = body(r);

        expect(text, contains('something happened #1999'));
        expect(text, isNot(contains('something happened #0\n')));
        expect(
          text,
          contains('latest ${r.logLinesIncluded} of 2000 lines, newest last'),
        );
      });
    }

    test('a bigger budget holds more of the log', () {
      final small = compose(
        BugReportChannel.email,
        logs: log(2000),
        maxUrlLength: 3000,
      );
      final large = compose(BugReportChannel.email, logs: log(2000));

      expect(small.uri.toString().length, lessThanOrEqualTo(3000));
      expect(small.logLinesIncluded, lessThan(large.logLinesIncluded));
    });

    test('a very small budget keeps the template and drops the rest', () {
      final r = compose(
        BugReportChannel.email,
        logs: log(100),
        maxUrlLength: kWindowsEmailUrlBudget,
      );

      expect(
        r.uri.toString().length,
        lessThanOrEqualTo(kWindowsEmailUrlBudget),
      );
      expect(body(r), contains('Describe the bug:'));
    });

    test('diagnostics come ahead of the log when space is short', () {
      final r = compose(
        BugReportChannel.github,
        logs: log(2000),
        diagnostics: [for (var i = 0; i < 9; i++) 'Diagnostic line $i'],
      );
      final text = body(r);

      for (var i = 0; i < 9; i++) {
        expect(text, contains('Diagnostic line $i'));
      }
      expect(
        text.indexOf('Diagnostic line 0'),
        lessThan(text.indexOf('Recent log')),
      );
    });

    test('with no log, leaves the log section out', () {
      final text = body(compose(BugReportChannel.github, logs: const []));

      expect(text, isNot(contains('Recent log')));
      expect(text, contains('Diagnostics'));
    });

    test('keeps UIDs and saved names out of the log, even ones just added', () {
      final r = compose(
        BugReportChannel.github,
        logs: [
          LogEntry(base, 'W', 'lookup for Aceu failed'),
          LogEntry(base, 'E', 'GET /bridge?uid=1006838015507 -> 500'),
          LogEntry(base, 'I', 'owner 1006838015507 / MR TORGUE signed in'),
        ],
        names: ['Aceu', 'Mr Torgue'],
      );
      final text = body(r);

      expect(text, isNot(contains('Aceu')));
      expect(text, isNot(contains('1006838015507')));
      expect(text.toLowerCase(), isNot(contains('torgue')));
      expect(text, contains('<name>'));
    });

    test('the link survives characters that mean something in a URL', () {
      final r = compose(
        BugReportChannel.github,
        logs: [LogEntry(base, 'W', 'odd chars: & = ? # % + " < > ``` ok')],
      );

      expect(body(r), contains('odd chars: & = ? # % + " < > ``` ok'));
    });
  });
}
