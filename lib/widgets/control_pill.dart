import 'package:flutter/material.dart';

import '../utils/theme.dart';

/// A small accent pill with an icon and a label, optionally led by a muted
/// [prefix] such as `Sort:`. Used for the controls that open a choice sheet,
/// and for quick actions.
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

  /// The least height the tappable area has, so a thumb can hit the pill.
  static const double minHitHeight = 40;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppTheme.accent;
    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: AppTheme.xs,
      ),
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
    );
    final lead = prefix;
    // The prefix is part of the control: a tap on it counts, and a screen
    // reader announces both as one button.
    return Semantics(
      button: true,
      label: lead == null ? label : '$lead $label',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHitHeight),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lead != null) ...[
                  Text(lead, style: AppTheme.caption),
                  const SizedBox(width: 4),
                ],
                pill,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
