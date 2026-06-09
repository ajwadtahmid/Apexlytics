import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/api_constants.dart';
import '../../providers/api_provider.dart';
import '../../utils/notifications.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart';
import 'widgets/cache_settings_section.dart';
import 'widgets/general_settings_section.dart';
import 'widgets/notification_settings_section.dart';
import 'widgets/stats_refresh_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static String _buildBugReportUrl(String version) {
    final body = Uri.encodeComponent(
      '**App version:** $version\n'
      '**Platform:** ${Platform.operatingSystem}\n'
      '**OS version:** ${Platform.operatingSystemVersion}\n\n'
      '**Describe the bug**\n'
      '<!-- What happened? What did you expect? -->\n\n'
      '**Steps to reproduce**\n'
      '1. \n'
      '2. \n\n'
      '**Additional context**\n'
      '<!-- Screenshots, logs, etc. -->',
    );
    return 'https://github.com/ajwadtahmid/Unofficial-Apex-Companion/issues/new?body=$body';
  }

  static String _buildBugReportEmailUrl(String version) {
    final body = Uri.encodeComponent(
      'App version: $version\n'
      'Platform: ${Platform.operatingSystem}\n'
      'OS version: ${Platform.operatingSystemVersion}\n\n'
      'Describe the bug:\n'
      '(What happened? What did you expect?)\n\n'
      'Steps to reproduce:\n'
      '1. \n'
      '2. \n\n'
      'Additional context:\n'
      '(Screenshots, logs, etc.)',
    );
    return 'mailto:aj22@duck.com?subject=Unofficial+Apex+Companion+Bug+Report&body=$body';
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
                _SupportRow(
                  icon: Icons.bug_report_outlined,
                  label: 'Report a bug (GitHub)',
                  url: _buildBugReportUrl(
                    ref.watch(packageInfoProvider).whenOrNull(data: (info) => info.version) ?? '—',
                  ),
                ),
                const Divider(color: AppTheme.surface2, height: 24),
                _SupportRow(
                  icon: Icons.mail_outline,
                  label: 'Report a bug (Email)',
                  url: _buildBugReportEmailUrl(
                    ref.watch(packageInfoProvider).whenOrNull(data: (info) => info.version) ?? '—',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.md),

          // ── Credits ─────────────────────────────────────
          const SectionLabel(label: 'Credits', icon: Icons.info_outline),
          const SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinkRow(
                  label: 'apexlegendsstatus.com',
                  subtitle: 'Server status. You can check this website for more information.',
                  url: ApiConstants.apexStatusUrl,
                ),
                Divider(color: AppTheme.surface2, height: 24),
                LinkRow(
                  label: 'apexlegendsapi.com',
                  subtitle: 'Player stats & legend data are provided by this API.',
                  url: ApiConstants.apexApiUrl,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.xl),
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    final version = ref.read(packageInfoProvider).whenOrNull(data: (info) => info.version) ?? '—';
                    Clipboard.setData(ClipboardData(text: version));
                    context.showMessage('Version copied', duration: const Duration(seconds: 2));
                  },
                  child: Text(
                    'Version ${ref.watch(packageInfoProvider).whenOrNull(data: (info) => info.version) ?? '—'}',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: AppTheme.xs),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppTheme.lg),
                  child: Text(
                    'Apexlytics is an unofficial companion app. Not made by, affiliated with, or endorsed by Electronic Arts or Respawn Entertainment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
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
