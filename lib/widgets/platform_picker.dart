import 'package:flutter/material.dart';
import '../constants/api_constants.dart';
import '../utils/theme.dart';

/// Platform selector pills.
///
/// [expanded] = true  → equal-width pills filling the row (setup / change-player sheets)
/// [expanded] = false → horizontally scrollable pills (search bar)
class PlatformPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final bool expanded;

  const PlatformPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final pills = ApiConstants.platforms.map((p) {
      final sel = p == selected;
      final pill = InkWell(
        onTap: () => onChanged(p),
        borderRadius: BorderRadius.circular(
          expanded ? AppTheme.radiusMd : AppTheme.radiusSm,
        ),
        child: AnimatedContainer(
          duration: AppTheme.chipAnimation,
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 0 : 14,
            vertical: expanded ? 10 : 6,
          ),
          decoration: BoxDecoration(
            color: sel ? AppTheme.accent : AppTheme.surface2,
            borderRadius: BorderRadius.circular(
              expanded ? AppTheme.radiusMd : AppTheme.radiusSm,
            ),
          ),
          child: Text(
            ApiConstants.platformLabels[p] ?? p,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: sel ? Colors.white : AppTheme.muted,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      );

      if (expanded) {
        return Expanded(
          child: Padding(padding: const EdgeInsets.only(right: 6), child: pill),
        );
      }
      return Padding(padding: const EdgeInsets.only(right: AppTheme.sm), child: pill);
    }).toList();

    if (expanded) return Row(children: pills);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: pills),
    );
  }
}
