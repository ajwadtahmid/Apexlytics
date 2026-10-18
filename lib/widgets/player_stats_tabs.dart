import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/legend_constants.dart';
import '../models/player_stats.dart';
import '../providers/legend_list_options_provider.dart';
import '../utils/formatting/format.dart' show timeAgo;
import '../utils/theme.dart';
import '../utils/tracking/legend_stat_sort.dart';
import 'legend_stats_section.dart';
import 'weapon_stats_section.dart';
import 'control_pill.dart';
import 'segmented_capsule.dart';
import 'sheet_handle.dart';

class PlayerStatsTabs extends ConsumerStatefulWidget {
  final List<LegendStat> legendStats;
  final List<String> legendStack;

  const PlayerStatsTabs({
    super.key,
    required this.legendStats,
    this.legendStack = const [],
  });

  @override
  ConsumerState<PlayerStatsTabs> createState() => _PlayerStatsTabsState();
}

class _PlayerStatsTabsState extends ConsumerState<PlayerStatsTabs> {
  int _tab = 0;

  // Memoized sort — recomputed only when inputs change.
  List<LegendStat> _cachedSorted = const [];
  List<LegendStat>? _prevLegendStats;
  List<String>? _prevLegendStack;
  LegendStatSort? _prevSort;
  bool? _prevReversed;

  // The memo holds the stat objects themselves, which the Legends list
  // renders, and the Kills/Damage/Wins sorts read their values - so a new list
  // (a refresh) must replace it even when the legend names are unchanged.
  // Rebuilds that pass the same list keep it.
  static bool _legendStatsChanged(
    List<LegendStat>? prev,
    List<LegendStat> next,
  ) => prev == null || !identical(prev, next);

  List<LegendStat> _sortedLegends(LegendListOptions options) {
    if (_legendStatsChanged(_prevLegendStats, widget.legendStats) ||
        !listEquals(_prevLegendStack, widget.legendStack) ||
        _prevSort != options.sort ||
        _prevReversed != options.reversed) {
      _cachedSorted = sortLegendStats(
        widget.legendStats,
        options.sort,
        recentStack: widget.legendStack,
        reversed: options.reversed,
      );
      _prevLegendStats = widget.legendStats;
      _prevLegendStack = widget.legendStack;
      _prevSort = options.sort;
      _prevReversed = options.reversed;
    }
    return _cachedSorted;
  }

  List<LegendStat> _displayedLegends(LegendListOptions options) {
    final sorted = _sortedLegends(options);
    final role = options.role;
    if (role == null) return sorted;
    return sorted.where((l) => legendInfo(l.name)?.role == role).toList();
  }

  /// When any legend's totals last moved, or null when none says.
  DateTime? get _lastChanged {
    DateTime? latest;
    for (final l in widget.legendStats) {
      final at = l.lastUpdated;
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(legendListOptionsProvider);
    final changed = _lastChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SegmentedCapsule(
            options: const ['Legends', 'Guns'],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        const SizedBox(height: AppTheme.sm),
        Text(
          'Career totals from the trackers each legend has equipped.'
          '${changed == null ? '' : ' Last changed ${timeAgo(changed)}.'}',
          textAlign: TextAlign.center,
          style: AppTheme.caption,
        ),
        if (_tab == 0) ...[
          const SizedBox(height: AppTheme.sm),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppTheme.md,
              runSpacing: AppTheme.xs,
              children: [
                ControlPill(
                  prefix: 'Filter:',
                  icon: Icons.apps,
                  // Orange on All, as each role has its own colour.
                  color: options.role?.color ?? AppTheme.accent,
                  // The role's own badge once one is chosen.
                  leading: options.role == null
                      ? null
                      : Image.asset(
                          options.role!.iconAsset,
                          width: 13,
                          height: 13,
                          color: options.role!.color,
                          colorBlendMode: BlendMode.srcIn,
                          cacheWidth:
                              (13 * MediaQuery.devicePixelRatioOf(context))
                                  .ceil(),
                        ),
                  label: options.role?.displayName ?? 'All',
                  onTap: () => _showFilterSheet(context),
                ),
                ControlPill(
                  prefix: 'Sort:',
                  icon: options.reversed
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  label: options.sort.label,
                  onTap: () => _showSortSheet(context),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppTheme.md),
        if (_tab == 0)
          LegendStatsSection(legends: _displayedLegends(options))
        else
          WeaponStatsSection(legendStats: widget.legendStats),
      ],
    );
  }
}

void _showSortSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SortSheet(),
  );
}

IconData _sortIcon(LegendStatSort sort) => switch (sort) {
  LegendStatSort.recent => Icons.access_time,
  LegendStatSort.kills => Icons.sports_kabaddi,
  LegendStatSort.damage => Icons.bolt,
  LegendStatSort.wins => Icons.emoji_events,
  LegendStatSort.role => Icons.category,
};

/// Which end of the order is on top, in words.
String _orderText(LegendStatSort sort, bool reversed) => switch (sort) {
  LegendStatSort.recent =>
    reversed ? 'Least recent first' : 'Most recent first',
  LegendStatSort.role =>
    '${(reversed ? kRoleDisplayOrder.last : kRoleDisplayOrder.first).displayName} first',
  _ => reversed ? 'Lowest first' : 'Highest first',
};

/// Every order the Legends tab offers; the one in use is marked with its
/// direction, and choosing it again turns it round.
class _SortSheet extends ConsumerWidget {
  const _SortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(legendListOptionsProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.md,
          AppTheme.md,
          AppTheme.md,
          AppTheme.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: AppTheme.md),
            const Text(
              'Sort legends by',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            const Text(
              'Choose the current one again to turn it round.',
              style: AppTheme.caption,
            ),
            const SizedBox(height: AppTheme.sm),
            for (final sort in LegendStatSort.values)
              _SortTile(
                sort: sort,
                selected: sort == options.sort,
                reversed: options.reversed,
                onTap: () {
                  ref.read(legendListOptionsProvider.notifier).choose(sort);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  final LegendStatSort sort;
  final bool selected;
  final bool reversed;
  final VoidCallback onTap;

  const _SortTile({
    required this.sort,
    required this.selected,
    required this.reversed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.accent : AppTheme.textPrimary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_sortIcon(sort), size: 20, color: color),
      title: Text(
        sort.label,
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: selected
          ? Text(_orderText(sort, reversed), style: AppTheme.caption)
          : null,
      trailing: selected
          ? Icon(
              reversed ? Icons.arrow_upward : Icons.arrow_downward,
              size: 18,
              color: AppTheme.accent,
            )
          : null,
      onTap: onTap,
    );
  }
}

void _showFilterSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _FilterSheet(),
  );
}

/// The roles the Legends tab can be narrowed to, and every legend; the one in
/// use is lit in the accent colour, "All" included.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(legendListOptionsProvider).role;
    void choose(LegendRole? role) {
      ref.read(legendListOptionsProvider.notifier).setRole(role);
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.md,
          AppTheme.md,
          AppTheme.md,
          AppTheme.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: AppTheme.md),
            const Text(
              'Filter legends by role',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.sm),
            _FilterTile(
              label: 'All',
              icon: const Icon(Icons.apps, size: 20),
              selected: current == null,
              onTap: () => choose(null),
            ),
            for (final role in kRoleDisplayOrder)
              _FilterTile(
                label: role.displayName,
                roleIcon: role.iconAsset,
                roleColor: role.color,
                selected: current == role,
                onTap: () => choose(role),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  final String label;
  final Widget? icon;
  final String? roleIcon;
  final Color? roleColor;
  final bool selected;
  final VoidCallback onTap;

  const _FilterTile({
    required this.label,
    this.icon,
    this.roleIcon,
    this.roleColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.accent : AppTheme.textPrimary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: roleIcon == null
          ? IconTheme(
              data: const IconThemeData(color: AppTheme.accent),
              child: icon!,
            )
          : Image.asset(
              roleIcon!,
              width: 20,
              height: 20,
              color: selected ? AppTheme.accent : roleColor,
              colorBlendMode: BlendMode.srcIn,
              cacheWidth: (20 * MediaQuery.devicePixelRatioOf(context)).ceil(),
            ),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, size: 18, color: AppTheme.accent)
          : null,
      onTap: onTap,
    );
  }
}
