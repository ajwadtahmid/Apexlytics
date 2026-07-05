import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/api_provider.dart';
import '../../utils/onboarding.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart';
import 'about_screen.dart';
import 'widgets/cache_settings_section.dart';
import 'widgets/general_settings_section.dart';
import 'widgets/notification_settings_section.dart';
import 'widgets/stats_refresh_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static String _buildBugReportUrl(String version, String buildNumber) {
    final body = Uri.encodeComponent(
      '**Describe the bug**\n'
      '<!-- What happened? What did you expect? -->\n\n'
      '**Steps to reproduce**\n'
      '1. \n'
      '2. \n\n'
      '**Additional context**\n'
      '<!-- Screenshots, logs, etc. -->\n\n'
      '---\n\n'
      '**App version:** $version ($buildNumber)\n'
      '**Platform:** ${Platform.operatingSystem}\n'
      '**OS version:** ${Platform.operatingSystemVersion}',
    );
    return 'https://github.com/ajwadtahmid/Apexlytics/issues/new?body=$body';
  }

  static String _buildBugReportEmailUrl(String version, String buildNumber) {
    final body = Uri.encodeComponent(
      'Describe the bug:\n'
      '(What happened? What did you expect?)\n\n'
      'Steps to reproduce:\n'
      '1. \n'
      '2. \n\n'
      'Additional context:\n'
      '(Screenshots, logs, etc.)\n\n'
      '---\n\n'
      'App version: $version ($buildNumber)\n'
      'Platform: ${Platform.operatingSystem}\n'
      'OS version: ${Platform.operatingSystemVersion}',
    );
    return 'mailto:support@ajwadtahmid.com?subject=Apexlytics+Bug+Report&body=$body';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
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
          SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(builder: (context) {
                  final info = ref.watch(packageInfoProvider).whenOrNull(data: (info) => info);
                  final version = info?.version ?? '—';
                  final build = info?.buildNumber ?? '—';
                  return Column(
                    children: [
                      _SupportRow(
                        icon: Icons.bug_report_outlined,
                        label: 'Report a bug (GitHub)',
                        url: _buildBugReportUrl(version, build),
                      ),
                      const Divider(color: AppTheme.surface2, height: 24),
                      _SupportRow(
                        icon: Icons.mail_outline,
                        label: 'Report a bug (Email)',
                        url: _buildBugReportEmailUrl(version, build),
                      ),
                    ],
                  );
                }),
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
                  icon: Icons.explore_outlined,
                  label: 'Take the tour',
                  onTap: () => unawaited(openOnboarding(context)),
                ),
                const Divider(color: AppTheme.surface2, height: 24),
                ActionRow(
                  icon: Icons.info_outline,
                  label: 'About Apexlytics',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                  ),
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

class _SupportRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _SupportRow({
    required this.icon,
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: () => unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textPrimary, size: 20),
          const SizedBox(width: AppTheme.sm),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          const Icon(Icons.open_in_new, color: AppTheme.muted, size: 14),
        ],
      ),
    );
  }
}
