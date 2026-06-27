import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/map_rotation.dart';
import '../utils/app_logger.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String _channelId = 'map_rotation_v2';

  static const _androidChannel = AndroidNotificationDetails(
    _channelId,
    'Map Rotation',
    channelDescription: 'Alerts before the map rotates',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _details = NotificationDetails(
    android: _androidChannel,
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> init() async {
    if (_initialized) return;
    if (!_supportsScheduled) return;
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
    _initialized = true;
    log.i('NotificationService initialised');
  }

  static Future<bool> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    bool granted = false;
    if (android != null) {
      granted = await android.requestNotificationsPermission() ?? false;
    } else if (ios != null) {
      granted = await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    log.i('Notification permission granted=$granted');
    return granted;
  }

  /// Whether the current platform supports local notifications and background fetch.
  static bool get _supportsScheduled => Platform.isAndroid || Platform.isIOS;

  // Each mode owns a contiguous block of [_maxPerMode] notification IDs so a
  // batch of upcoming-rotation alerts can be scheduled — and cancelled —
  // cleanly. IDs 1–10 stay reserved for future categories (RP milestones, etc.).
  static const _maxPerMode = 12;
  static const _rankedIdBase = 100; // 100–111
  static const _pubsIdBase = 120; // 120–131
  static const _ltmIdBase = 140; // 140–151
  static const _wildcardIdBase = 160; // 160–171

  // Legacy single-notification IDs (pre-batch). Cancelled on every schedule so
  // they don't linger after an app update.
  static const _legacyIds = [11, 12, 13, 14];

  // iOS keeps only the 64 soonest-firing pending notifications and silently
  // drops the rest, so cap the total well under that. 4 modes × 12 = 48 worst
  // case, but enforce defensively in case modes/horizon grow.
  static const _maxTotalScheduled = 56;

  /// Schedules a batch of upcoming-rotation notifications per enabled mode and
  /// cancels any previously scheduled ones.
  ///
  /// The API only reports the current and next map, so only the next rotation's
  /// map name is known; later rotations are projected from [MapMode.durationMins]
  /// with generic copy. Batching means the OS (AlarmManager / UNUserNotification
  /// Center) holds hours of alerts and fires them while the app is suspended —
  /// the app no longer has to be open to re-arm each one.
  ///
  /// Each mode has its own [minutesBefore] timing.
  /// [favoriteRankedMapNames] / [favoritePubsMapNames] filter alerts by map.
  static Future<void> scheduleAll(
    MapRotation rotation, {
    bool notifyRanked = false,
    int rankedMinutesBefore = 0,
    bool notifyPubs = false,
    int pubsMinutesBefore = 0,
    bool notifyMixtape = false,
    int mixtapeMinutesBefore = 0,
    bool notifyWildcard = false,
    int wildcardMinutesBefore = 0,
    List<String> favoriteRankedMapNames = const [],
    List<String> favoritePubsMapNames = const [],
  }) async {
    if (!_supportsScheduled) return;

    // Cancel legacy IDs and every per-mode block so stale alerts don't linger.
    // Other notification channels (IDs 1–10) are left untouched.
    final idsToCancel = <int>[..._legacyIds];
    for (final base in [
      _rankedIdBase,
      _pubsIdBase,
      _ltmIdBase,
      _wildcardIdBase,
    ]) {
      for (var i = 0; i < _maxPerMode; i++) {
        idsToCancel.add(base + i);
      }
    }
    await Future.wait(idsToCancel.map((id) => _plugin.cancel(id: id)));

    var budget = _maxTotalScheduled;

    if (notifyRanked && rankedMinutesBefore > 0) {
      budget -= await _scheduleModeSeries(
        _rankedIdBase,
        'Ranked',
        rotation.rankedNext,
        rotation.rankedCurrent.remainingSecs,
        rankedMinutesBefore,
        budget,
        favoriteMapNames: favoriteRankedMapNames,
      );
    }
    if (notifyPubs && pubsMinutesBefore > 0) {
      budget -= await _scheduleModeSeries(
        _pubsIdBase,
        'Pubs',
        rotation.battleRoyaleNext,
        rotation.battleRoyaleCurrent.remainingSecs,
        pubsMinutesBefore,
        budget,
        favoriteMapNames: favoritePubsMapNames,
      );
    }
    if (notifyMixtape &&
        mixtapeMinutesBefore > 0 &&
        rotation.ltmCurrent != null &&
        rotation.ltmNext != null) {
      budget -= await _scheduleModeSeries(
        _ltmIdBase,
        'Mixtape',
        rotation.ltmNext!,
        rotation.ltmCurrent!.remainingSecs,
        mixtapeMinutesBefore,
        budget,
      );
    }
    if (notifyWildcard &&
        wildcardMinutesBefore > 0 &&
        rotation.wildcardCurrent != null &&
        rotation.wildcardNext != null) {
      budget -= await _scheduleModeSeries(
        _wildcardIdBase,
        'Wildcards',
        rotation.wildcardNext!,
        rotation.wildcardCurrent!.remainingSecs,
        wildcardMinutesBefore,
        budget,
      );
    }
  }

  /// Schedules a series of upcoming-rotation notifications for one mode, up to
  /// [_maxPerMode] or the remaining [budget], and returns how many were
  /// scheduled. Only the first rotation's map name is known; later rotations
  /// are projected from [nextMap.durationMins] with generic copy.
  static Future<int> _scheduleModeSeries(
    int idBase,
    String modeLabel,
    MapMode nextMap,
    int currentRemainingSecs,
    int minutesBefore,
    int budget, {
    List<String> favoriteMapNames = const [],
  }) async {
    if (budget <= 0) return 0;

    final now = tz.TZDateTime.now(tz.UTC);
    final durationSecs = nextMap.durationMins * 60;
    final filtering = favoriteMapNames.isNotEmpty;

    var rotationStartSecs = currentRemainingSecs;
    var scheduled = 0;

    for (var i = 0; i < _maxPerMode && scheduled < budget; i++) {
      final knownMap = i == 0;

      // The favourites filter only applies to the one map we actually know (the
      // next rotation). If it isn't a favourite, stop — we can't predict whether
      // later maps qualify.
      if (knownMap && filtering && !favoriteMapNames.contains(nextMap.map)) {
        log.d('$modeLabel notification skipped (map not in favourites)');
        break;
      }

      final notifyAt = now
          .add(Duration(seconds: rotationStartSecs))
          .subtract(Duration(minutes: minutesBefore));

      if (notifyAt.isAfter(now)) {
        final unit = minutesBefore == 1 ? 'minute' : 'minutes';
        final body = knownMap
            ? '$modeLabel: ${_mapDisplay(nextMap)} starts in $minutesBefore $unit'
            : '$modeLabel: Next map starts in $minutesBefore $unit';
        await _plugin.zonedSchedule(
          id: idBase + i,
          title: 'Apexlytics',
          body: body,
          scheduledDate: notifyAt,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        scheduled++;
      }

      // Can't project further without a known cadence, or when filtering (future
      // map names are unknown, so unfilterable).
      if (durationSecs <= 0 || filtering) break;
      rotationStartSecs += durationSecs;
    }

    log.d('$modeLabel: scheduled $scheduled notification(s)');
    return scheduled;
  }

  static String _mapDisplay(MapMode m) =>
      m.eventName != null && m.eventName!.isNotEmpty
      ? '${m.map} (${m.eventName})'
      : m.map;

  static Future<void> cancelAll() async => _plugin.cancelAll();
}
