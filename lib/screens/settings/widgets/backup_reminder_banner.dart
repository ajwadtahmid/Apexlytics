import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/backup_status_provider.dart';
import '../../../providers/navigation_provider.dart';
import '../../../utils/backup_reminder.dart';
import '../../../utils/formatting/format.dart' show plural;
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';
import 'cache_settings_section.dart' show exportData;

/// A nudge at the top of Settings once [kBackupReminderAfter] has passed with
/// games recorded that no backup holds. Match history lives only on the device,
/// and the app cannot rebuild it. Gone as soon as a backup is made.
class BackupReminderBanner extends ConsumerWidget {
  const BackupReminderBanner({super.key});

  /// The line under the title: how many games, and since when.
  @visibleForTesting
  static String message(BackupStatus status, DateTime now) {
    final games = plural(status.newGames, 'game');
    final last = status.lastBackup;
    return last == null
        ? '$games recorded, and none backed up yet.'
        : '$games recorded since your last backup, '
              '${backupAgeLabel(last, now)}.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Games are recorded while this page is out of view, so count afresh each
    // time it is opened.
    ref.listen(currentTabProvider, (_, tab) {
      if (tab == AppTab.settings) ref.invalidate(backupStatusProvider);
    });
    final now = DateTime.now();
    final status = ref.watch(backupStatusProvider).asData?.value;
    if (status == null || !status.isDue(now)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.md),
      child: SurfaceCard(
        padding: const EdgeInsets.all(AppTheme.md),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
        child: Row(
          children: [
            const Icon(Icons.backup_outlined, color: AppTheme.accent, size: 22),
            const SizedBox(width: AppTheme.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Back up your match history',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(message(status, now), style: AppTheme.captionLarge),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.sm),
            TextButton(
              onPressed: () => exportData(context, ref),
              child: const Text(
                'Export',
                style: TextStyle(color: AppTheme.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
