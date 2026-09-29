import 'package:flutter/material.dart';
import '../utils/theme.dart';

class StatDisplay extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final bool compact;

  /// Overrides the value text's color (e.g. green/red for a signed RP figure)
  /// without changing the surrounding chip style. Takes precedence over
  /// [highlight] when set.
  final Color? valueColor;

  const StatDisplay({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
    this.compact = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = highlight ? AppTheme.accent : AppTheme.muted;
    final valueColor =
        this.valueColor ?? (highlight ? AppTheme.accent : AppTheme.textPrimary);
    final labelSize = compact ? 9.0 : 10.0;
    final valueSize = compact ? 12.0 : 15.0;
    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 7);

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: highlight ? AppTheme.accent.withAlpha(25) : AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: labelSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: valueSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stat chips split into [groups] (e.g. RP/record, combat, playtime) by a
/// thin divider — no section labels needed since the chip labels say enough.
class GroupedStatChips extends StatelessWidget {
  final List<List<Widget>> groups;
  final WrapAlignment alignment;
  const GroupedStatChips({
    super.key,
    required this.groups,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0)
            const Divider(color: AppTheme.surface2, height: AppTheme.lg),
          // Forces full width so a single-line Wrap has room to center in,
          // rather than shrinking to its content and pinning left.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: alignment,
              spacing: AppTheme.sm,
              runSpacing: AppTheme.sm,
              children: groups[i],
            ),
          ),
        ],
      ],
    );
  }
}
