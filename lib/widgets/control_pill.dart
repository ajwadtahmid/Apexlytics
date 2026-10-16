import 'package:flutter/material.dart';

import '../utils/theme.dart';

/// A small accent pill with an icon and a label, optionally led by a muted
/// [prefix] such as `Sort:`. Used for cycling sort controls and quick actions.
class ControlPill extends StatelessWidget {
  final String? prefix;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ControlPill({
    super.key,
    this.prefix,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pill = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppTheme.xs),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppTheme.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
    final lead = prefix;
    if (lead == null) return pill;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          lead,
          style: AppTheme.caption,
        ),
        const SizedBox(width: 4),
        pill,
      ],
    );
  }
}
