import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/theme.dart';
import '../../../widgets/widgets.dart';
import '../map_alerts_sheet.dart';

class NotificationSettingsSection extends ConsumerWidget {
  const NotificationSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playerSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel(label: 'Notifications', icon: Icons.notifications_outlined),
        SettingsCard(
          child: InkWell(
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
                  _notifSummary(settings),
                  style: TextStyle(
                    color: _anyActive(settings) ? AppTheme.accent : AppTheme.muted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: AppTheme.xs),
                const Icon(Icons.chevron_right, color: AppTheme.muted, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static bool _anyActive(PlayerSettings settings) =>
      (settings.notifyRankedMapRotation && settings.rankedNotifyMinutesBefore > 0) ||
      (settings.notifyPubsMapRotation && settings.pubsNotifyMinutesBefore > 0) ||
      (settings.notifyWildcardMapRotation && settings.wildcardNotifyMinutesBefore > 0) ||
      (settings.notifyMixtapeMapRotation && settings.mixtapeNotifyMinutesBefore > 0);

  static String _notifSummary(PlayerSettings settings) {
    final count = [
      settings.notifyRankedMapRotation && settings.rankedNotifyMinutesBefore > 0,
      settings.notifyPubsMapRotation && settings.pubsNotifyMinutesBefore > 0,
      settings.notifyWildcardMapRotation && settings.wildcardNotifyMinutesBefore > 0,
      settings.notifyMixtapeMapRotation && settings.mixtapeNotifyMinutesBefore > 0,
    ].where((b) => b).length;
    return count == 0 ? 'Off' : '$count active';
  }
}
