import 'package:flutter/material.dart';

import '../utils/theme.dart';

/// A small accent pill with an icon and a label, optionally led by a muted
/// [prefix] such as `Sort:`. Used for cycling sort controls and quick actions.
class ControlPill extends StatelessWidget {
  final String? prefix;
  final IconData icon;

  /// Drawn in place of [icon] when given, for a picture that isn't an icon
  /// glyph (a role's badge, say). It should be about 13 px square.
  final Widget? leading;

  /// Tints the whole pill, as a role badge is, and colours its label and icon.
  /// Null keeps the plain accent pill.
  final Color? color;
  final String label;

  /// Drawn after the label, such as which way a sort runs. About 13 px square.
  final Widget? trailing;
  final VoidCallback onTap;

  const ControlPill({
    super.key,
    this.prefix,
    required this.icon,
    this.leading,
    this.color,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppTheme.accent;
    final pill = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppTheme.xs),
        decoration: BoxDecoration(
          color: color == null ? AppTheme.surface2 : color!.withAlpha(35),
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading ?? Icon(icon, size: 13, color: tint),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: tint,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
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
