import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/map_rotation.dart';
import '../utils/app_logger.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Desktop has no OS-level scheduler or background wakeup, so pending alerts
  // are held as in-app timers and fire only while the app is running. They are
  // re-armed on every fetch and cancelled wholesale, mirroring [cancelAll].
  static final List<Timer> _desktopTimers = [];

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
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  static Future<void> init() async {
    if (_initialized) return;
    if (!_supported) return;
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open Apexlytics',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Apexlytics',
      appUserModelId: 'Apexlytics.Apexlytics',
      // Stable GUID identifying this app's notification activation callback.
      guid: 'b8e7d3a2-9f1c-4e6b-8a7d-2c5f0e1a4b3c',
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
        windows: windowsSettings,
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

    final macos = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
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
    } else if (macos != null) {
      granted = await macos.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    } else {
      // Linux/Windows require no runtime notification permission.
      granted = _supportsImmediate;
    }
    log.i('Notification permission granted=$granted');
    return granted;
  }

  /// Mobile platforms hold scheduled alerts at the OS level and support
  /// background fetch, so notifications fire even when the app is closed.
  static bool get _supportsScheduled => Platform.isAndroid || Platform.isIOS;

  /// Desktop platforms can show notifications while the app is running but have
  /// no OS scheduler or background wakeup — alerts are fired by in-app timers
  /// and stop when the app exits.
  static bool get _supportsImmediate =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  static bool get _supported => _supportsScheduled || _supportsImmediate;

  // Each mode owns a contiguous block of [_maxPerMode] notification IDs so a
  // batch of upcoming-rotation alerts can be scheduled — and cancelled —
  // cleanly. IDs 1–10 stay reserved for future categories (RP milestones, etc.).
  static const _maxPerMode = 12;
  static const _rankedIdBase = 100; // 100–111
  static const _pubsIdBase = 120; // 120–131
  static const _ltmIdBase = 140; // 140–151
  static const _wildcardIdBase = 160; // 160–171

  // iOS keeps only the 64 soonest-firing pending notifications and silently
  // drops the rest, so cap the total well under that. 4 modes × 12 = 48 worst
  // case, but enforce defensively in case modes/horizon grow.
  static const _maxTotalScheduled = 56;

  /// Schedules a batch of upcoming-rotation notifications per enabled mode and
  /// cancels any previously scheduled ones.
  ///
  /// [rotation] reports the current and next map with timing. For Ranked and
  /// Pubs, [rankedSequence] / [pubsSequence] give the full cyclic rotation order
  /// (from the `/maps` endpoint), so every projected rotation can be named — not
  /// just the next one. Mixtape/Wildcard have no sequence, so rotations past the
  /// next are projected from [MapMode.durationMins] with generic copy. Batching
  /// means the OS (AlarmManager / UNUserNotificationCenter) holds hours of alerts
  /// and fires them while the app is suspended; on desktop they fire via in-app
  /// timers while the app runs.
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
    List<String> rankedSequence = const [],
    List<String> pubsSequence = const [],
  }) async {
    if (!_supported || !_initialized) return;

    await _cancelAllInternal();

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
        mapSequence: rankedSequence,
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
        mapSequence: pubsSequence,
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
  /// scheduled.
  ///
  /// When [mapSequence] (the cyclic rotation order) is provided, every projected
  /// rotation is named by walking the cycle from [nextMap]'s position. Without
  /// it, only the next rotation is named and later ones use generic copy.
  static Future<int> _scheduleModeSeries(
    int idBase,
    String modeLabel,
    MapMode nextMap,
    int currentRemainingSecs,
    int minutesBefore,
    int budget, {
    List<String> favoriteMapNames = const [],
    List<String> mapSequence = const [],
  }) async {
    if (budget <= 0) return 0;

    final now = tz.TZDateTime.now(tz.UTC);
    final durationSecs = nextMap.durationMins * 60;
    final filtering = favoriteMapNames.isNotEmpty;

    // Where the next map sits in the rotation cycle. Rotation i is then
    // sequence[(nextIndex + i) % length], so future maps can be named.
    final nextIndex = mapSequence.indexOf(nextMap.map);
    final hasSequence = nextIndex >= 0;

    var rotationStartSecs = currentRemainingSecs;
    var scheduled = 0;

    for (var i = 0; i < _maxPerMode && scheduled < budget; i++) {
      // The map name for rotation i: the live next map for i==0, otherwise
      // projected from the cycle. Null means we can't identify it.
      final String? mapName = i == 0
          ? nextMap.map
          : (hasSequence
                ? mapSequence[(nextIndex + i) % mapSequence.length]
                : null);

      // Favourites filter: skip rotations whose map isn't a favourite. Without a
      // known name we can't tell, so stop projecting.
      if (filtering) {
        if (mapName == null) break;
        if (!favoriteMapNames.contains(mapName)) {
          if (durationSecs <= 0) break;
          rotationStartSecs += durationSecs;
          continue;
        }
      }

      final notifyAt = now
          .add(Duration(seconds: rotationStartSecs))
          .subtract(Duration(minutes: minutesBefore));

      if (notifyAt.isAfter(now)) {
        final unit = minutesBefore == 1 ? 'minute' : 'minutes';
        final String body;
        if (i == 0) {
          body = '$modeLabel: ${_mapDisplay(nextMap)} starts in $minutesBefore $unit';
        } else if (mapName != null) {
          body = '$modeLabel: $mapName starts in $minutesBefore $unit';
        } else {
          body = '$modeLabel: Next map starts in $minutesBefore $unit';
        }
        await _dispatch(idBase + i, body, notifyAt, now);
        scheduled++;
      }

      // Can't project further rotations without a known cadence.
      if (durationSecs <= 0) break;
      rotationStartSecs += durationSecs;
    }

    log.d('$modeLabel: scheduled $scheduled notification(s)');
    return scheduled;
  }

  /// Arms a single alert. Mobile hands it to the OS scheduler so it fires even
  /// when the app is closed; desktop sets an in-app timer that fires [show]
  /// only while the app keeps running.
  static Future<void> _dispatch(
    int id,
    String body,
    tz.TZDateTime at,
    tz.TZDateTime now,
  ) async {
    if (_supportsScheduled) {
      await _plugin.zonedSchedule(
        id: id,
        title: 'Apexlytics',
        body: body,
        scheduledDate: at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } else {
      _desktopTimers.add(
        Timer(at.difference(now), () {
          _plugin.show(
            id: id,
            title: 'Apexlytics',
            body: body,
            notificationDetails: _details,
          );
        }),
      );
    }
  }

  static String _mapDisplay(MapMode m) =>
      m.eventName != null && m.eventName!.isNotEmpty
      ? '${m.map} (${m.eventName})'
      : m.map;

  static Future<void> cancelAll() async {
    if (!_initialized) return;
    await _cancelAllInternal();
  }

  static Future<void> _cancelAllInternal() async {
    for (final t in _desktopTimers) {
      t.cancel();
    }
    _desktopTimers.clear();
    await _plugin.cancelAll();
  }
}
