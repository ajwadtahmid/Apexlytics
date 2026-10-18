import 'package:flutter/material.dart';
import '../constants/legend_constants.dart';
import '../utils/theme.dart';
import 'legend_asset_image.dart';
import 'role_badge.dart';

/// The top of a legend's detail sheets: a rounded square portrait, the name and
/// the role badge. Shared so the ranked Legends tab and the trackers sheet look
/// the same.
class LegendHeader extends StatelessWidget {
  /// The legend's API name; "Global" is shown as the career entry.
  final String name;
  const LegendHeader({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final info = legendInfo(name);
    final display = legendDisplayName(name);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: SizedBox(
            width: 84,
            height: 84,
            child: LegendAssetImage(
              imageKey: legendImageKey(name),
              displayName: display,
              fallbackFontSize: 30,
            ),
          ),
        ),
        const SizedBox(width: AppTheme.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shrinks a long name at a large text size rather than breaking
              // it mid-word.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  display,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (info != null) ...[
                const SizedBox(height: 8),
                RoleBadge(role: info.role),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
