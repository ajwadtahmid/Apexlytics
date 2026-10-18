import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/bug_report_provider.dart';
import '../../utils/bug_report.dart' show BugReportChannel;
import '../../utils/onboarding.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart';
import 'about_screen.dart';
import 'widgets/backup_reminder_banner.dart';
import 'widgets/cache_settings_section.dart';
import 'widgets/general_settings_section.dart';
import 'widgets/notification_settings_section.dart';
import 'widgets/stats_refresh_section.dart';
import '../../utils/navigation_utils.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          const BackupReminderBanner(),
          const GeneralSettingsSection(),
          const SizedBox(height: AppTheme.md),
          const StatsRefreshSection(),
          const SizedBox(height: AppTheme.md),
          const NotificationSettingsSection(),
          const SizedBox(height: AppTheme.md),
          const CacheSettingsSection(),
          const SizedBox(height: AppTheme.md),

          // ── Support ─────────────────────────────────────
          const SectionLabel(label: 'Support', icon: Icons.help_outline),
          const SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SupportRow(
                  icon: Icons.bug_report_outlined,
                  label: 'Report a bug (GitHub)',
                  channel: BugReportChannel.github,
                ),
                Divider(color: AppTheme.surface2, height: 24),
                _SupportRow(
                  icon: Icons.mail_outline,
                  label: 'Report a bug (Email)',
                  channel: BugReportChannel.email,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.md),

          // ── About ─────────────────────────────────────
          const SectionLabel(label: 'About', icon: Icons.info_outline),
          SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ActionRow(
                  icon: Icons.info_outline,
                  label: 'About Apexlytics',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                ),
                const Divider(color: AppTheme.surface2, height: 24),
                ActionRow(
                  icon: Icons.explore_outlined,
                  label: 'Take the tour',
                  onTap: () => unawaited(openOnboarding(context)),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.xl),
        ],
      ),
    );
  }
}

/// Opens a bug report prefilled with the version, a few diagnostics and the
/// recent log (see [bugReportProvider]).
class _SupportRow extends ConsumerWidget {
  final IconData icon;
  final String label;
  final BugReportChannel channel;

  const _SupportRow({
    required this.icon,
    required this.label,
    required this.channel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: () async {
        final report = await ref.read(bugReportProvider(channel).future);
        if (!context.mounted) return;
        await openExternalLink(context, report.uri);
      },
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textPrimary, size: 20),
          const SizedBox(width: AppTheme.sm),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          const Icon(Icons.open_in_new, color: AppTheme.muted, size: 14),
        ],
      ),
    );
  }
}
