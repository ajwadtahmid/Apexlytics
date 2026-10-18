import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../services/background_service.dart';
import '../services/map_notification_service.dart';
import '../services/notification_service.dart';
import 'app_logger.dart';
import 'notifications.dart';
import 'theme.dart';

/// The modes that have a map rotation alert.
enum MapAlertMode {
  pubs('Pubs'),
  ranked('Ranked'),
  wildcard('Wildcards'),
  mixtape('Mixtape');

  /// How the Home mode picker and the alerts sheet name it.
  final String label;
  const MapAlertMode(this.label);

  /// The mode shown under [label] on Home, or null for a label with no alert.
  static MapAlertMode? fromLabel(String label) {
    for (final mode in values) {
      if (mode.label == label) return mode;
    }
    return null;
  }
}

const _kDefaultBattleRoyaleMinutes = 15;
const _kDefaultOtherModesMinutes = 10;

extension MapAlertSettingsX on PlayerSettings {
  bool alertEnabled(MapAlertMode mode) => switch (mode) {
    MapAlertMode.ranked => notifyRankedMapRotation,
    MapAlertMode.pubs => notifyPubsMapRotation,
    MapAlertMode.wildcard => notifyWildcardMapRotation,
    MapAlertMode.mixtape => notifyMixtapeMapRotation,
  };

  /// Minutes before a rotation the alert fires; 0 means off.
  int alertMinutes(MapAlertMode mode) => switch (mode) {
    MapAlertMode.ranked => rankedNotifyMinutesBefore,
    MapAlertMode.pubs => pubsNotifyMinutesBefore,
    MapAlertMode.wildcard => wildcardNotifyMinutesBefore,
    MapAlertMode.mixtape => mixtapeNotifyMinutesBefore,
  };

  /// An alert is on when the mode is switched on and has a lead time.
  bool alertActive(MapAlertMode mode) =>
      alertEnabled(mode) && alertMinutes(mode) > 0;
}

/// Plans the alerts again from the current rotation. Delegates to the call Home
/// makes, so every caller names the upcoming map the same way.
Future<void> rescheduleMapAlerts(WidgetRef ref) async {
  try {
    final result = await ref.read(mapRotationProvider.future);
    MapNotificationService.schedule(ref, result.data);
  } catch (e) {
    log.w('Notification reschedule failed', error: e);
  }
}

/// Switches [mode]'s alert on, at the lead time it last had or a default, and
/// asks for notification permission. Returns whether the permission is held.
Future<bool> turnOnMapAlert(
  BuildContext context,
  WidgetRef ref,
  MapAlertMode mode,
) async {
  final notifier = ref.read(playerSettingsProvider.notifier);

  // Set the lead time BEFORE switching the mode on so the settings listener
  // never sees mode=ON with timing=0 (which would trigger cancelAll).
  if (ref.read(playerSettingsProvider).alertMinutes(mode) == 0) {
    switch (mode) {
      case MapAlertMode.ranked:
        await notifier.setRankedNotifyMinutesBefore(
          _kDefaultBattleRoyaleMinutes,
        );
      case MapAlertMode.pubs:
        await notifier.setPubsNotifyMinutesBefore(_kDefaultBattleRoyaleMinutes);
      case MapAlertMode.wildcard:
        await notifier.setWildcardNotifyMinutesBefore(
          _kDefaultOtherModesMinutes,
        );
      case MapAlertMode.mixtape:
        await notifier.setMixtapeNotifyMinutesBefore(
          _kDefaultOtherModesMinutes,
        );
    }
  }

  var granted = false;
  try {
    granted = await NotificationService.requestPermissions();
  } catch (e) {
    // No notification plugin to ask: the same as being refused.
    log.w('Notification permission request failed', error: e);
  }
  if (!context.mounted) return granted;
  if (!granted) {
    context.showMessage(
      'Enable notifications in system settings to receive alerts',
    );
  }

  switch (mode) {
    case MapAlertMode.pubs:
      await notifier.setNotifyPubsMapRotation(true);
    case MapAlertMode.ranked:
      await notifier.setNotifyRankedMapRotation(true);
    case MapAlertMode.wildcard:
      await notifier.setNotifyWildcardMapRotation(true);
    case MapAlertMode.mixtape:
      await notifier.setNotifyMixtapeMapRotation(true);
  }

  await rescheduleMapAlerts(ref);
  if (!context.mounted) return granted;
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    final available = await BackgroundService.isAvailable();
    if (!available && context.mounted) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Background Refresh Disabled'),
          content: const Text(
            'Notifications will only fire while the app is open.\n\n'
            'To get alerts when the app is closed, enable Background App '
            'Refresh in:\niOS Settings → General → Background App Refresh '
            '→ Apexlytics',
            style: TextStyle(color: AppTheme.muted, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        ),
      );
    }
  }
  return granted;
}
