import 'package:flutter/material.dart';
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
      padding: const EdgeInsets.only(bottom: 12, left: AppTheme.xs),
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
