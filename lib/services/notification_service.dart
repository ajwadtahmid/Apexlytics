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
      '@mipmap/ic_launcher',
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

  // IDs 11–14 are reserved for per-mode map-rotation notifications.
  // IDs 1–10 are reserved for future notification categories (RP milestones, etc.).
  static const _notifIdRanked = 11;
  static const _notifIdPubs = 12;
  static const _notifIdLtm = 13;
  static const _notifIdWildcard = 14;

  /// Schedule up to 3 notifications (one per mode) and cancel any old ones.
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
    // Cancel only the known map-rotation IDs so other notification channels
    // (e.g. future RP-milestone alerts) are not silently wiped.
    await Future.wait([
      _plugin.cancel(id: _notifIdRanked),
      _plugin.cancel(id: _notifIdPubs),
      _plugin.cancel(id: _notifIdLtm),
      _plugin.cancel(id: _notifIdWildcard),
    ]);

    if (notifyRanked && rankedMinutesBefore > 0) {
      await _scheduleMode(
        _notifIdRanked,
        'Ranked',
        rotation.rankedNext,
        rotation.rankedCurrent.remainingSecs,
        rankedMinutesBefore,
        favoriteMapNames: favoriteRankedMapNames,
      );
    }
    if (notifyPubs && pubsMinutesBefore > 0) {
      await _scheduleMode(
        _notifIdPubs,
        'Pubs',
        rotation.battleRoyaleNext,
        rotation.battleRoyaleCurrent.remainingSecs,
        pubsMinutesBefore,
        favoriteMapNames: favoritePubsMapNames,
      );
    }
    if (notifyMixtape &&
        mixtapeMinutesBefore > 0 &&
        rotation.ltmCurrent != null &&
        rotation.ltmNext != null) {
      await _scheduleMode(
        _notifIdLtm,
        'Mixtape',
        rotation.ltmNext!,
        rotation.ltmCurrent!.remainingSecs,
        mixtapeMinutesBefore,
      );
    }
    if (notifyWildcard &&
        wildcardMinutesBefore > 0 &&
        rotation.wildcardCurrent != null &&
        rotation.wildcardNext != null) {
      await _scheduleMode(
        _notifIdWildcard,
        'Wildcards',
        rotation.wildcardNext!,
        rotation.wildcardCurrent!.remainingSecs,
        wildcardMinutesBefore,
      );
    }
  }

  static Future<void> _scheduleMode(
    int id,
    String modeLabel,
    MapMode nextMap,
    int currentRemainingSecs,
    int minutesBefore, {
    List<String> favoriteMapNames = const [],
  }) async {
    if (favoriteMapNames.isNotEmpty && !favoriteMapNames.contains(nextMap.map)) {
      log.d('$modeLabel notification skipped (map not in favourites)');
      return;
    }

    final notifyAt = tz.TZDateTime.now(tz.UTC)
        .add(Duration(seconds: currentRemainingSecs))
        .subtract(Duration(minutes: minutesBefore));

    if (!notifyAt.isAfter(tz.TZDateTime.now(tz.UTC))) {
      log.d('$modeLabel notification skipped (fire time already passed)');
      return;
    }

    log.d('$modeLabel notification scheduled in ${minutesBefore}min');
    await _plugin.zonedSchedule(
      id: id,
      title: '$modeLabel · Map Rotation',
      body: '${nextMap.map} starts in $minutesBefore min',
      scheduledDate: notifyAt,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancelAll() async => _plugin.cancelAll();
}
