import 'package:flutter/material.dart';
import '../constants/legend_constants.dart';
import '../utils/theme.dart';

/// Colored pill showing a legend's [LegendRole]: class icon + name, tinted
/// with [LegendRole.color]. The same pill was previously duplicated
/// (text-only) across the legend card, legend detail page, and ranked
/// legend detail sheet — kept as one widget here so all three stay in sync.
class RoleBadge extends StatelessWidget {
  final LegendRole role;

  /// Smaller sizing for the legend list card; the detail-page/sheet headers
  /// use the default (larger) sizing.
  final bool compact;

  const RoleBadge({super.key, required this.role, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? 10.0 : 12.0;
    final iconSize = compact ? 10.0 : 12.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: role.color.withAlpha(35),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            role.iconAsset,
            width: iconSize,
            height: iconSize,
            color: role.color,
            colorBlendMode: BlendMode.srcIn,
            cacheWidth: (iconSize * MediaQuery.devicePixelRatioOf(context))
                .ceil(),
          ),
          const SizedBox(width: 4),
          Text(
            role.displayName,
            style: TextStyle(
              color: role.color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
