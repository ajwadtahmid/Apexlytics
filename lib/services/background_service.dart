import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:background_fetch/background_fetch.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../constants/api_constants.dart';
import '../env/env.dart';
import '../models/background_fetch_settings.dart';
import '../models/map_rotation.dart';
import '../models/seasonal_maps.dart';
import '../utils/api_base_options.dart';
import '../utils/app_logger.dart';
import '../utils/retry_interceptor.dart';
import 'notification_service.dart';

const int _backgroundFetchIntervalMinutes = 30;

/// Outcome of the most recent background fetch, as `ok:<iso8601>` or
/// `error:<iso8601>`. Surfaced in Settings - background fetch is otherwise
/// completely invisible, and "are my map alerts actually being rescheduled?"
/// has no other answer from inside the app.
const String kLastFetchResultKey = 'bg_fetch_last_result';

/// `debugPrint` is **not** stripped in release builds, and this runs in a
/// detached isolate where the app logger and Sentry may not be initialised -
/// hence print rather than log. Gating on [kDebugMode] keeps routine progress
/// chatter out of production logcat.
void _debugLog(String message) {
  if (kDebugMode) debugPrint('[BackgroundService] $message');
}

/// Reads the cached rotation order written by the foreground /maps provider.
/// Returns null if absent or unparseable — callers fall back to generic copy.
SeasonalMaps? _cachedSeasonalMaps(SharedPreferences prefs) {
  final jsonStr = prefs.getString(SeasonalMaps.cacheKey);
  if (jsonStr == null) return null;
  try {
    return SeasonalMaps.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

// Runs when the app is fully terminated (headless). Must be top-level.
@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessEvent event) async {
  if (event.timeout) {
    _debugLog('Task timed out: ${event.taskId}');
    BackgroundFetch.finish(event.taskId);
    return;
  }
  try {
    await _backgroundFetchAndSchedule();
  } finally {
    BackgroundFetch.finish(event.taskId);
  }
}

Future<void> _backgroundFetchAndSchedule() async {
  SharedPreferences? prefs;
  try {
    _debugLog('Fetch started');
    tz.initializeTimeZones();
    await NotificationService.init();

    prefs = await SharedPreferences.getInstance();
    final settings = BackgroundFetchSettings.fromPrefs(prefs);
    if (settings == null) {
      // No modes enabled — actively cancel rather than leaving whatever was
      // last scheduled armed. "Clear all data" hits exactly this path: it
      // wipes every notification pref but nothing else here would otherwise
      // tear down alerts scheduled before the clear.
      await NotificationService.cancelAll();
      return;
    }

    // Headless tasks run in a detached isolate — no provider tree is available,
    // so ApiService cannot be used here. Create a minimal Dio client directly,
    // with the same primary/backup failover ApiService gets.
    final dio = Dio(buildApiBaseOptions());
    dio.interceptors.add(
      RetryInterceptor(dio: dio, backupBaseUrl: Env.proxyUrlBackup),
    );

    final response = await dio.get(
      ApiConstants.mapRotationPath,
      queryParameters: {'version': ApiConstants.mapRotationVersion},
    );

    final rotation = MapRotation.fromJson(
      response.data as Map<String, dynamic>,
    );

    // The cyclic rotation order (cached by the foreground /maps provider) lets
    // every projected Ranked/Pubs alert be named. The isolate has no provider
    // tree, so read it straight from prefs; absence just falls back to generic.
    final seasonal = _cachedSeasonalMaps(prefs);

    await NotificationService.scheduleAll(
      rotation,
      notifyPubs: settings.notifyPubs,
      pubsMinutesBefore: settings.pubsMinutesBefore,
      notifyRanked: settings.notifyRanked,
      rankedMinutesBefore: settings.rankedMinutesBefore,
      notifyMixtape: settings.notifyMixtape,
      mixtapeMinutesBefore: settings.mixtapeMinutesBefore,
      notifyWildcard: settings.notifyWildcard,
      wildcardMinutesBefore: settings.wildcardMinutesBefore,
      favoriteRankedMapNames: settings.favoriteRankedMapNames,
      favoritePubsMapNames: settings.favoritePubsMapNames,
      rankedSequence: seasonal?.rankedNames ?? const [],
      pubsSequence: seasonal?.pubsNames ?? const [],
    );
    // scheduleAll is a silent no-op when the plugin never finished
    // initialising — without this check, that skip reads as a successful
    // run here, and Settings' "Last background refresh" row would then
    // claim alerts are armed when nothing was actually scheduled.
    if (!NotificationService.isInitialized) {
      throw StateError('Notification service failed to initialise');
    }
    _debugLog('Notifications scheduled successfully');
    await prefs.setString(
      kLastFetchResultKey,
      'ok:${DateTime.now().toIso8601String()}',
    );
  } catch (e) {
    // Detail only in debug: this string can carry a host name or an upstream
    // message, and debugPrint is not stripped from release builds.
    _debugLog('Fetch failed: $e');
    try {
      prefs ??= await SharedPreferences.getInstance();
      // Timestamp only. The reason used to be appended here, which put an
      // exception string into a pref that a support screenshot could carry
      // off the device.
      await prefs.setString(
        kLastFetchResultKey,
        'error:${DateTime.now().toIso8601String()}',
      );
    } catch (e2) {
      _debugLog('Failed to persist error flag: $e2');
    }
  }
}

class BackgroundService {
  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  static BackgroundFetchConfig _config(int intervalMinutes) =>
      BackgroundFetchConfig(
        minimumFetchInterval: intervalMinutes,
        stopOnTerminate: false,
        enableHeadless: true,
        startOnBoot: true,
      );

  static Future<void> _configure(
    int intervalMinutes,
  ) => BackgroundFetch.configure(
    _config(intervalMinutes),
    (String taskId) async {
      try {
        await _backgroundFetchAndSchedule();
      } finally {
        BackgroundFetch.finish(taskId);
      }
    },
    // Timeout handler — invoked if the task doesn't finish within the deadline.
    (String taskId) => BackgroundFetch.finish(taskId),
  );

  static Future<void> init() async {
    if (!_supported) return;
    try {
      await _configure(_backgroundFetchIntervalMinutes);
    } on PlatformException catch (e) {
      // iOS UIBackgroundRefreshStatus: "0" restricted, "1" denied.
      if (Platform.isIOS && (e.code == '0' || e.code == '1')) {
        log.w('Background fetch unavailable on this device (status ${e.code})');
        return;
      }
      rethrow;
    }
    if (Platform.isAndroid) {
      BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
    }
    log.i(
      'BackgroundService initialised (interval: ${_backgroundFetchIntervalMinutes}min)',
    );
  }

  /// Reconfigures the background fetch interval to the smallest active
  /// notification timing. Pass [minNotifyMinutes] == 0 to fall back to the
  /// default 30-min cadence.
  static Future<void> updateInterval(int minNotifyMinutes) async {
    if (!_supported) return;
    // iOS and Android enforce a 15-min minimum for background fetch — values
    // below 15 (e.g. user picks 5 or 10 min) are silently rounded up by the OS.
    final interval = minNotifyMinutes > 0
        ? minNotifyMinutes.clamp(15, 60)
        : _backgroundFetchIntervalMinutes;
    await _configure(interval);
    log.i('BackgroundService interval updated to ${interval}min');
  }

  /// Returns true if background fetch is available.
  /// On Android this is always true. On iOS it depends on the system setting.
  static Future<bool> isAvailable() async {
    if (!_supported) return false;
    final status = await BackgroundFetch.status;
    return status == BackgroundFetch.STATUS_AVAILABLE;
  }
}
