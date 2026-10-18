import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/bug_report_provider.dart';
import 'package:apexlytics/providers/search_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/providers/storage_usage_provider.dart';
import 'package:apexlytics/utils/app_logger.dart';
import 'package:apexlytics/utils/bug_report.dart';
import 'package:apexlytics/utils/log_buffer.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../helpers.dart';

void main() {
  setUp(LogBuffer.instance.clear);
  tearDown(LogBuffer.instance.clear);

  List<Override> overrides({
    int games = 2333,
    int historyBytes = 1258291,
    int cached = 42,
    int cacheBytes = 90000,
  }) => [
    packageInfoProvider.overrideWith(
      (ref) async => PackageInfo(
        appName: 'Apexlytics',
        packageName: 'app.test',
        version: '1.4.0',
        buildNumber: '27',
      ),
    ),
    storageUsageProvider.overrideWith(
      (ref) async => StorageUsage(
        games: games,
        historyBytes: historyBytes,
        cachedResponses: cached,
        cacheBytes: cacheBytes,
      ),
    ),
  ];

  String textOf(BugReport built) {
    final url = built.uri.toString();
    return Uri.decodeComponent(url.substring(url.indexOf('body=') + 5));
  }

  Future<String> report(
    BugReportChannel channel, {
    Map<String, Object> prefs = const {},
    bool withProfile = true,
  }) async {
    final (container, _) = await prefsContainer(
      values: prefs,
      overrides: overrides(),
    );
    if (withProfile) {
      await container
          .read(playerSettingsProvider.notifier)
          .setPlayer('Aceu', '1006838015507', 'PS4');
    }
    return textOf(await container.read(bugReportProvider(channel).future));
  }

  test('carries the version, the diagnostics and the recent log', () async {
    LogBuffer.instance.add('I', 'service ready');
    LogBuffer.instance.add('W', 'retrying after 503');

    final text = await report(BugReportChannel.github);

    expect(text, contains('**App version:** 1.4.0 (27)'));
    expect(text, contains('Profiles: 1 (PS4)'));
    expect(text, contains('Match history: 2,333 games, 1.2 MB'));
    expect(text, contains('Cached responses: 42, 88 KB'));
    expect(text, contains('Alerts on: none'));
    expect(text, contains('service ready'));
    expect(text, contains('retrying after 503'));
  });

  test('reads the last background result, when there is one', () async {
    final at = DateTime.now().subtract(const Duration(hours: 5));
    final text = await report(
      BugReportChannel.email,
      prefs: {PrefsKeys.bgFetchLastResult: 'error:${at.toIso8601String()}'},
    );

    expect(text, contains('last failed 5h ago'));
  });

  test('says when no background run was ever recorded', () async {
    final text = await report(BugReportChannel.email);

    expect(text, contains('last never recorded'));
  });

  test('lists the alerts that are on, with their lead time', () async {
    final (container, _) = await prefsContainer(overrides: overrides());
    final settings = container.read(playerSettingsProvider.notifier);
    await settings.setRankedNotifyMinutesBefore(15);
    await settings.setNotifyRankedMapRotation(true);
    // On, but with no lead time: not an alert that will fire.
    await settings.setNotifyPubsMapRotation(true);

    final text = textOf(
      await container.read(bugReportProvider(BugReportChannel.github).future),
    );

    expect(text, contains('Alerts on: Ranked 15 min\n'));
  });

  test('keeps the saved name and UID out, even from the log', () async {
    LogBuffer.instance.add('W', 'lookup for Aceu failed');
    LogBuffer.instance.add('E', 'GET /bridge?uid=1006838015507 -> 500');
    LogBuffer.instance.add('I', 'compared with Rival123');
    final (container, _) = await prefsContainer(overrides: overrides());
    await container
        .read(playerSettingsProvider.notifier)
        .setPlayer('Aceu', '1006838015507', 'PC');
    // A favorite: someone the app knows by name too.
    await container
        .read(searchStateProvider.notifier)
        .toggleFavorite(
          const PlayerRef(
            query: 'Rival123',
            platform: 'PC',
            searchedByUid: false,
          ),
        );

    final text = textOf(
      await container.read(bugReportProvider(BugReportChannel.github).future),
    );

    expect(text, isNot(contains('Aceu')));
    expect(text, isNot(contains('Rival123')));
    expect(text, isNot(contains('1006838015507')));
    expect(text, contains('<name>'));
  });

  test('still builds a report with no player and an empty log', () async {
    final text = await report(BugReportChannel.github, withProfile: false);

    expect(text, contains('Profiles: 0'));
    expect(text, contains('Diagnostics'));
    expect(text, isNot(contains('Recent log')));
  });
  test('whatever the app logs reaches the report, scrubbed', () async {
    log.i('service ready');
    log.w('retry for 1006838015507', error: Exception('uid=1006838015507'));

    final text = await report(BugReportChannel.github, withProfile: false);

    expect(text, contains(' I service ready'));
    expect(text, contains(' W retry for <uid>'));
    expect(text, isNot(contains('1006838015507')));
  });
  test('is built whole when read with nothing listening, however slow', () async {
    // The real checks take a moment; an unwatched provider is dropped in that
    // time unless it holds itself, which broke the report in the app.
    const pause = Duration(milliseconds: 80);
    final (container, _) = await prefsContainer(
      overrides: [
        packageInfoProvider.overrideWith((ref) async {
          await Future<void>.delayed(pause);
          return PackageInfo(
            appName: 'Apexlytics',
            packageName: 'app.test',
            version: '1.4.0',
            buildNumber: '27',
          );
        }),
        storageUsageProvider.overrideWith((ref) async {
          await Future<void>.delayed(pause);
          return const StorageUsage(
            games: 7,
            historyBytes: 4096,
            cachedResponses: 1,
            cacheBytes: 100,
          );
        }),
      ],
    );

    final built = await container.read(
      bugReportProvider(BugReportChannel.email).future,
    );
    final text = textOf(built);

    expect(text, contains('App version: 1.4.0 (27)'));
    expect(text, contains('Match history: 7 games, 4 KB'));
  });
}
