import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async' show unawaited;
import '../utils/theme.dart';
import 'icon_text_row.dart';
import 'surface_card.dart';

class SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const SectionLabel({super.key, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: IconTextRow(
        icon: icon,
        text: label,
        iconSize: 14,
        iconColor: AppTheme.accent,
        gap: 6,
        textStyle: const TextStyle(
          color: AppTheme.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  final Widget child;
  const SettingsCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}

class ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppTheme.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: onTap,
      child: IconTextRow(
        icon: icon,
        text: label,
        iconSize: 20,
        iconColor: color,
        textStyle: TextStyle(color: color, fontSize: 14),
      ),
    );
  }
}

class LinkRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final String url;
  const LinkRow({
    super.key,
    required this.label,
    required this.subtitle,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: () => unawaited(
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.blue,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.open_in_new, color: AppTheme.muted, size: 14),
        ],
      ),
    );
  }
}
