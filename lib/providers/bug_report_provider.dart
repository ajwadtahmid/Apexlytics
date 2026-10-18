import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/prefs_keys.dart';
import '../services/background_service.dart';
import '../services/notification_service.dart';
import '../utils/app_logger.dart';
import '../utils/bug_report.dart';
import '../utils/log_buffer.dart';
import '../utils/map_alert_actions.dart';
import 'api_provider.dart';
import 'backup_status_provider.dart';
import 'navigation_provider.dart';
import 'search_provider.dart';
import 'settings_provider.dart';
import 'storage_usage_provider.dart';

/// The bug report for a channel, built from what the app knows right now: its
/// version, a few diagnostics, and the recent log. See [composeBugReport] for
/// what is kept out and how the size is held down.
final bugReportProvider = FutureProvider.autoDispose
    .family<BugReport, BugReportChannel>((ref, channel) async {
      // Read with no listener, so left alone it would be disposed while it
      // still waits on the system below. Held until the report is built, then
      // let go.
      final link = ref.keepAlive();
      // The same for the count it reads, which is also dropped when unwatched.
      ref.listen(storageUsageProvider, (_, _) {});
      try {
        return await _buildReport(ref, channel);
      } finally {
        link.close();
      }
    });

Future<BugReport> _buildReport(Ref ref, BugReportChannel channel) async {
  final settings = ref.read(playerSettingsProvider);
  final prefs = ref.read(sharedPreferencesProvider);

  final info = await ref
      .read(packageInfoProvider.future)
      .then<({String version, String build})?>(
        (i) => (version: i.version, build: i.buildNumber),
        onError: (_) => null,
      );

  // Each of these may fail or not exist on a platform; a report with a gap
  // is better than none.
  Future<T?> tryGet<T>(Future<T> Function() read) async {
    try {
      return await read();
    } catch (e) {
      log.w('Bug report: a diagnostic could not be read (${e.runtimeType})');
      return null;
    }
  }

  final permitted = await tryGet(NotificationService.notificationsEnabled);
  final mobile = Platform.isAndroid || Platform.isIOS;
  final backgroundAvailable = mobile
      ? await tryGet(BackgroundService.isAvailable)
      : null;
  final usage = await tryGet(() => ref.read(storageUsageProvider.future));

  final raw = prefs.getString(PrefsKeys.bgFetchLastResult);
  final split = raw?.indexOf(':') ?? -1;
  final lastAt = split < 0
      ? null
      : DateTime.tryParse(raw!.substring(split + 1));
  final lastBackground = lastAt == null
      ? null
      : (ok: raw!.substring(0, split) == 'ok', at: lastAt);

  final facts = DiagnosticsFacts(
    locale: PlatformDispatcher.instance.locale.toString(),
    utcOffset: DateTime.now().timeZoneOffset,
    notificationsInitialised: NotificationService.isInitialized,
    notificationsPermitted: permitted,
    alertsOn: [
      for (final mode in MapAlertMode.values)
        if (settings.alertActive(mode))
          '${mode.label} ${settings.alertMinutes(mode)} min',
    ],
    backgroundAvailable: backgroundAvailable,
    lastBackground: lastBackground,
    profileCount: settings.profiles.length,
    platforms: [for (final p in settings.profiles) p.platform],
    defaultTab: appTabForDefault(settings.defaultTab).label,
    statsRefreshMinutes: settings.statsRefreshMinutes,
    keepScreenOn: settings.keepScreenOn,
    games: usage?.games,
    historyBytes: usage?.historyBytes,
    cachedResponses: usage?.cachedResponses,
    cacheBytes: usage?.cacheBytes,
    lastBackup: ref.read(lastBackupProvider),
  );

  final search = ref.read(searchStateProvider);
  return composeBugReport(
    channel,
    version: info?.version ?? '—',
    build: info?.build ?? '—',
    platform: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    diagnostics: diagnosticsLines(facts, DateTime.now()),
    logs: LogBuffer.instance.entries,
    // Whoever the app knows by name, so no log line can carry one out.
    names: [
      for (final p in settings.profiles) p.name,
      for (final r in [...search.favorites, ...search.recents]) r.query,
    ],
    maxUrlLength: channel == BugReportChannel.email && Platform.isWindows
        ? kWindowsEmailUrlBudget
        : null,
  );
}
