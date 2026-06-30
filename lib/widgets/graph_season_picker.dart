import 'package:flutter/material.dart';
import '../models/season_meta.dart';
import '../utils/theme.dart';

/// Season selector pill for [GraphCard]'s header row. Collapses to a static
/// label when there's only one season to choose from.
class SeasonPicker extends StatelessWidget {
  final String selectedId;
  final List<SeasonMeta> seasons;
  final ValueChanged<String> onSelected;

  const SeasonPicker({
    super.key,
    required this.selectedId,
    required this.seasons,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('No seasons'),
      );
    }

    final selected = seasons.firstWhere(
      (s) => s.id == selectedId,
      orElse: () => seasons.first,
    );
    final hasChoice = seasons.length > 1;

    final label = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selected.displayName,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.arrow_drop_down,
            size: 14,
            color: hasChoice ? AppTheme.accent : AppTheme.accent.withAlpha(120),
          ),
        ],
      ),
    );

    if (!hasChoice) return label;

    return PopupMenuButton<String>(
      initialValue: selectedId,
      onSelected: onSelected,
      color: AppTheme.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      itemBuilder: (_) => seasons
          .map(
            (s) => PopupMenuItem<String>(
              value: s.id,
              child: Text(
                s.displayName,
                style: TextStyle(
                  fontSize: 13,
                  color: s.id == selectedId
                      ? AppTheme.accent
                      : AppTheme.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
      child: label,
    );
  }
}
