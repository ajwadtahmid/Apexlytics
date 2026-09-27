import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../providers/notification_provider.dart';
import '../../../services/notification_service.dart';
import '../../../utils/theme.dart';

/// Warnings for the two ways an alert that looks switched on can silently
/// never fire: the notification plugin failed to init (`scheduleAll` is then
/// a no-op), or the OS permission is off. Shown only while [alertsActive],
/// each followed by [separator].
///
/// Shared by the Settings notifications card and the Map Alerts sheet, so
/// the place alerts are switched on says so too, not just the card above it.
class NotificationHealthBanners extends ConsumerWidget {
  final bool alertsActive;
  final Widget separator;

  const NotificationHealthBanners({
    super.key,
    required this.alertsActive,
    required this.separator,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Defaults to permitted while the check is in flight so the banner never
    // flashes on for users whose permission is actually fine.
    final permissionEnabled =
        ref.watch(notificationsEnabledProvider).whenOrNull(data: (v) => v) ??
        true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The plugin failed to initialise (e.g. both the primary and
        // fallback Android icon lookups threw) — scheduleAll is then a
        // silent no-op, so surface it rather than let a toggle claim alerts
        // are armed when nothing will fire.
        if (alertsActive && !NotificationService.isInitialized) ...[
          const _InitFailedBanner(),
          separator,
        ],
        if (alertsActive && !permissionEnabled) ...[
          const _PermissionBanner(),
          separator,
        ],
      ],
    );
  }
}

/// Shown when the user has at least one alert mode on but the notification
/// plugin never finished initialising, so scheduling is silently skipped —
/// see [NotificationService.isInitialized]. Init is retried each time the
/// app returns to the foreground, and on every restart.
class _InitFailedBanner extends StatelessWidget {
  const _InitFailedBanner();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.error_outline, color: AppTheme.red, size: 20),
        SizedBox(width: AppTheme.sm),
        Expanded(
          child: Text(
            "Alerts couldn't start — try restarting the app",
            style: TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}

/// Shown when the user has at least one alert mode on but the OS-level
/// notification permission has been denied or revoked, so the toggle would
/// otherwise silently do nothing.
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: openAppSettings,
      child: const Row(
        children: [
          Icon(Icons.notifications_off_outlined, color: AppTheme.red, size: 20),
          SizedBox(width: AppTheme.sm),
          Expanded(
            child: Text(
              'Notification permission off',
              style: TextStyle(fontSize: 14),
            ),
          ),
          Text('Fix', style: TextStyle(color: AppTheme.accent, fontSize: 14)),
          SizedBox(width: AppTheme.xs),
          Icon(Icons.chevron_right, color: AppTheme.muted, size: 18),
        ],
      ),
    );
  }
}
