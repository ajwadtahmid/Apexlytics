import 'package:flutter/material.dart';
import '../../../utils/theme.dart';
import '../../../widgets/icon_text_row.dart';

/// Tappable row for a notification mode (Ranked / Pubs / Mixtape).
/// Tap to toggle the mode on/off.
class MapModeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const MapModeTile({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppTheme.green : AppTheme.red;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.sm),
        child: Row(
          children: [
            AnimatedContainer(
              duration: AppTheme.shortAnimation,
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppTheme.sm),
            Icon(icon, size: 16, color: AppTheme.textPrimary),
            const SizedBox(width: AppTheme.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: enabled ? AppTheme.textPrimary : AppTheme.muted,
                ),
              ),
            ),
            Icon(
              enabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              size: 16,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable timing row shown beneath the mode tile when enabled.
class MapTimingTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const MapTimingTile({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.sm),
        child: Row(
          children: [
            const Icon(Icons.schedule_outlined, size: 14, color: AppTheme.muted),
            const SizedBox(width: AppTheme.sm),
            const Expanded(
              child: Text('Alert timing', style: TextStyle(fontSize: 13, color: AppTheme.muted)),
            ),
            Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.accent)),
            const SizedBox(width: AppTheme.xs),
            const Icon(Icons.chevron_right, size: 16, color: AppTheme.muted),
          ],
        ),
      ),
    );
  }
}

/// Tappable row to reveal hidden (unselected, non-proxy) maps.
class MapExpandTile extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const MapExpandTile({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppTheme.md,
          top: AppTheme.sm,
          bottom: AppTheme.sm,
        ),
        child: IconTextRow(
          icon: Icons.add_circle_outline,
          text: '$count more map${count == 1 ? '' : 's'}',
          iconSize: 14,
          iconColor: AppTheme.muted,
          textStyle: const TextStyle(fontSize: 13, color: AppTheme.muted),
        ),
      ),
    );
  }
}

/// Individual map row with a green/red indicator for notify state.
class MapAlertTile extends StatelessWidget {
  final String name;
  final bool notify;
  final VoidCallback onTap;

  const MapAlertTile({
    super.key,
    required this.name,
    required this.notify,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = notify ? AppTheme.green : AppTheme.red;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppTheme.md,
          top: AppTheme.sm,
          bottom: AppTheme.sm,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: AppTheme.shortAnimation,
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppTheme.sm),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  color: notify ? AppTheme.textPrimary : AppTheme.muted,
                ),
              ),
            ),
            Icon(
              notify
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              size: 16,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
