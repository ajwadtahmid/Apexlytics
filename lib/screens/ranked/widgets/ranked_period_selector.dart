import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/ranked_provider.dart';
import '../../../utils/ranked/ranked_period.dart';
import '../../../utils/theme.dart';

/// Split selector for the AppBar actions — a compact pill that opens the list
/// of available splits. Drives [rankedPeriodProvider].
class RankedSplitDropdown extends ConsumerWidget {
  final RankedView view;
  const RankedSplitDropdown({super.key, required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view.splits.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(rankedPeriodProvider.notifier);
    final selected = view.splits.firstWhere(
      (s) => s.id == view.effectiveSplitId,
      orElse: () => view.splits.first,
    );

    final pill = Container(
      margin: const EdgeInsets.only(right: AppTheme.sm),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selected.displayName,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (view.splits.length > 1) ...[
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.accent),
          ],
        ],
      ),
    );

    if (view.splits.length <= 1) return pill;

    return PopupMenuButton<String>(
      initialValue: selected.id,
      onSelected: notifier.selectSplit,
      color: AppTheme.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      itemBuilder: (_) => view.splits
          .map(
            (s) => PopupMenuItem<String>(
              value: s.id,
              child: Text(
                s.displayName,
                style: TextStyle(
                  fontSize: 13,
                  color: s.id == view.effectiveSplitId
                      ? AppTheme.accent
                      : AppTheme.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
      child: pill,
    );
  }
}

/// Week-chip strip hosted in the AppBar's `bottom` slot: `All · W1 · W2 …`, so
/// the split selector and weeks read as one cohesive header. Hidden for splits
/// with no week metadata (the "Other" bucket) — callers gate on `weeks`.
class RankedWeekStrip extends ConsumerWidget implements PreferredSizeWidget {
  final RankedView view;
  const RankedWeekStrip({super.key, required this.view});

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view.weeks.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(rankedPeriodProvider.notifier);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppTheme.md, 2, AppTheme.md, AppTheme.sm),
      // Centre the chips when they fit; fall back to horizontal scrolling when
      // there are too many weeks to fit on one line.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _WeekChip(
                  label: 'All',
                  selected: view.weekIndex < 0,
                  onTap: () => notifier.selectWeek(-1),
                ),
                for (var i = 0; i < view.weeks.length; i++)
                  _WeekChip(
                    label: 'W${i + 1}',
                    selected: view.weekIndex == i,
                    enabled: !view.weeks[i].start.isAfter(DateTime.now()),
                    onTap: () => notifier.selectWeek(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _WeekChip({
    required this.label,
    required this.selected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.surface2,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? Colors.white : AppTheme.muted,
            ),
          ),
        ),
      ),
    );
  }
}
