import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/theme.dart';
import '../../../widgets/widgets.dart';
import '../map_alerts_sheet.dart';

class NotificationSettingsSection extends ConsumerWidget {
  const NotificationSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifyRanked =
        ref.watch(playerSettingsProvider.select((s) => s.notifyRankedMapRotation));
    final rankedMinutes =
        ref.watch(playerSettingsProvider.select((s) => s.rankedNotifyMinutesBefore));
    final notifyPubs = ref.watch(playerSettingsProvider.select((s) => s.notifyPubsMapRotation));
    final pubsMinutes =
        ref.watch(playerSettingsProvider.select((s) => s.pubsNotifyMinutesBefore));
    final notifyWildcard =
        ref.watch(playerSettingsProvider.select((s) => s.notifyWildcardMapRotation));
    final wildcardMinutes =
        ref.watch(playerSettingsProvider.select((s) => s.wildcardNotifyMinutesBefore));
    final notifyMixtape =
        ref.watch(playerSettingsProvider.select((s) => s.notifyMixtapeMapRotation));
    final mixtapeMinutes =
        ref.watch(playerSettingsProvider.select((s) => s.mixtapeNotifyMinutesBefore));

    final active = [
      notifyRanked && rankedMinutes > 0,
      notifyPubs && pubsMinutes > 0,
      notifyWildcard && wildcardMinutes > 0,
      notifyMixtape && mixtapeMinutes > 0,
    ];
    final activeCount = active.where((b) => b).length;

    // Defaults to permitted while the check is in flight so the banner never
    // flashes on for users whose permission is actually fine.
    final permissionEnabled =
        ref.watch(notificationsEnabledProvider).whenOrNull(data: (v) => v) ?? true;
    final showPermissionBanner = activeCount > 0 && !permissionEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel(label: 'Notifications', icon: Icons.notifications_outlined),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showPermissionBanner) ...[
                const _PermissionBanner(),
                const Divider(color: AppTheme.surface2, height: 24),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                onTap: () => showMapAlertsSheet(context),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_outlined, color: AppTheme.textPrimary, size: 20),
                    const SizedBox(width: AppTheme.sm),
                    const Expanded(
                      child: Text('Map rotation alerts', style: TextStyle(fontSize: 14)),
                    ),
                    Text(
                      activeCount == 0 ? 'Off' : '$activeCount active',
                      style: TextStyle(
                        color: activeCount > 0 ? AppTheme.accent : AppTheme.muted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: AppTheme.xs),
                    const Icon(Icons.chevron_right, color: AppTheme.muted, size: 18),
                  ],
                ),
              ),
            ],
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
            child: Text('Notification permission off', style: TextStyle(fontSize: 14)),
          ),
          Text(
            'Fix',
            style: TextStyle(color: AppTheme.accent, fontSize: 14),
          ),
          SizedBox(width: AppTheme.xs),
          Icon(Icons.chevron_right, color: AppTheme.muted, size: 18),
        ],
      ),
    );
  }
}
