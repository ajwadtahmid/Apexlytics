import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import '../constants/legend_constants.dart';
import '../models/player_stats.dart';
import '../utils/theme.dart';
import 'legend_stats_section.dart';
import 'weapon_stats_section.dart';

enum _LegendSortOrder { byLastPlayed, byKills, byDamage, byWins, byRole }

class PlayerStatsTabs extends StatefulWidget {
  final List<LegendStat> legendStats;
  final bool compact;
  final List<String> legendStack;

  const PlayerStatsTabs({
    super.key,
    required this.legendStats,
    this.compact = false,
    this.legendStack = const [],
  });

  @override
  State<PlayerStatsTabs> createState() => _PlayerStatsTabsState();
}

class _PlayerStatsTabsState extends State<PlayerStatsTabs> {
  int _tab = 0;
  _LegendSortOrder _sort = _LegendSortOrder.byLastPlayed;
  LegendRole? _roleFilter;

  // Memoized sort — recomputed only when inputs change.
  List<LegendStat> _cachedSorted = const [];
  List<LegendStat>? _prevLegendStats;
  List<String>? _prevLegendStack;
  _LegendSortOrder? _prevSort;

  // Sort order depends only on legend names (not tracker values), so compare
  // by name to avoid spurious re-sorts when the provider emits new instances
  // containing identical data.
  static bool _legendStatsChanged(
    List<LegendStat>? prev,
    List<LegendStat> next,
  ) {
    if (prev == null) return true;
    if (identical(prev, next)) return false;
    if (prev.length != next.length) return true;
    for (var i = 0; i < next.length; i++) {
      if (prev[i].name != next[i].name) return true;
    }
    return false;
  }

  List<LegendStat> get _sortedLegends {
    if (_legendStatsChanged(_prevLegendStats, widget.legendStats) ||
        !listEquals(_prevLegendStack, widget.legendStack) ||
        _prevSort != _sort) {
      _cachedSorted = _computeSorted();
      _prevLegendStats = widget.legendStats;
      _prevLegendStack = widget.legendStack;
      _prevSort = _sort;
    }
    return _cachedSorted;
  }

  List<LegendStat> get _displayedLegends {
    final sorted = _sortedLegends;
    if (_roleFilter == null) return sorted;
    return sorted
        .where((l) => kLegendsByName[l.name.toLowerCase()]?.role == _roleFilter)
        .toList();
  }

  List<LegendStat> _computeSorted() {
    final list = List<LegendStat>.from(widget.legendStats);
    final originalIndex = {for (var i = 0; i < list.length; i++) list[i].name: i};
    switch (_sort) {
      case _LegendSortOrder.byKills:
        list.sort((a, b) {
          final k = b.killCount.compareTo(a.killCount);
          if (k != 0) return k;
          final d = b.damageDealt.compareTo(a.damageDealt);
          if (d != 0) return d;
          final w = b.winsCount.compareTo(a.winsCount);
          if (w != 0) return w;
          return originalIndex[a.name]!.compareTo(originalIndex[b.name]!);
        });
      case _LegendSortOrder.byDamage:
        list.sort((a, b) {
          final d = b.damageDealt.compareTo(a.damageDealt);
          if (d != 0) return d;
          final k = b.killCount.compareTo(a.killCount);
          if (k != 0) return k;
          final w = b.winsCount.compareTo(a.winsCount);
          if (w != 0) return w;
          return originalIndex[a.name]!.compareTo(originalIndex[b.name]!);
        });
      case _LegendSortOrder.byWins:
        list.sort((a, b) {
          final w = b.winsCount.compareTo(a.winsCount);
          if (w != 0) return w;
          final k = b.killCount.compareTo(a.killCount);
          if (k != 0) return k;
          final d = b.damageDealt.compareTo(a.damageDealt);
          if (d != 0) return d;
          return originalIndex[a.name]!.compareTo(originalIndex[b.name]!);
        });
      case _LegendSortOrder.byRole:
        list.sort((a, b) {
          final roleA = kLegendsByName[a.name.toLowerCase()]?.role ?? LegendRole.assault;
          final roleB = kLegendsByName[b.name.toLowerCase()]?.role ?? LegendRole.assault;
          final roleIdxA = kRoleDisplayOrder.indexOf(roleA);
          final roleIdxB = kRoleDisplayOrder.indexOf(roleB);
          if (roleIdxA != roleIdxB) return roleIdxA.compareTo(roleIdxB);
          final na = kLegendsByName[a.name.toLowerCase()]?.number ?? 999;
          final nb = kLegendsByName[b.name.toLowerCase()]?.number ?? 999;
          return na.compareTo(nb);
        });
      case _LegendSortOrder.byLastPlayed:
        // Stack-based "Recent" sort: legends visited most recently come first.
        // Legends not yet in the stack preserve their original API order.
        final stack = widget.legendStack;
        if (stack.isNotEmpty) {
          list.sort((a, b) {
            final ia = stack.indexOf(a.name);
            final ib = stack.indexOf(b.name);
            if (ia == -1 && ib == -1) return 0;
            if (ia == -1) return 1;
            if (ib == -1) return -1;
            return ia.compareTo(ib);
          });
        }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: _SegmentedCapsule(
            options: const ['Legends', 'Guns'],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ),
        if (_tab == 0) ...[
          const SizedBox(height: AppTheme.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'Sort:',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() {
                  _sort = switch (_sort) {
                    _LegendSortOrder.byLastPlayed => _LegendSortOrder.byKills,
                    _LegendSortOrder.byKills => _LegendSortOrder.byDamage,
                    _LegendSortOrder.byDamage => _LegendSortOrder.byWins,
                    _LegendSortOrder.byWins => _LegendSortOrder.byRole,
                    _LegendSortOrder.byRole => _LegendSortOrder.byLastPlayed,
                  };
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        switch (_sort) {
                          _LegendSortOrder.byLastPlayed => Icons.access_time,
                          _LegendSortOrder.byKills => Icons.sports_kabaddi,
                          _LegendSortOrder.byDamage => Icons.bolt,
                          _LegendSortOrder.byWins => Icons.emoji_events,
                          _LegendSortOrder.byRole => Icons.category,
                        },
                        size: 13,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        switch (_sort) {
                          _LegendSortOrder.byLastPlayed => 'Recent',
                          _LegendSortOrder.byKills => 'Kills',
                          _LegendSortOrder.byDamage => 'Damage',
                          _LegendSortOrder.byWins => 'Wins',
                          _LegendSortOrder.byRole => 'Role',
                        },
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.sm),
          // Role filter chips
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _RoleChip(
                    label: 'All',
                    selected: _roleFilter == null,
                    color: AppTheme.muted,
                    onTap: () => setState(() => _roleFilter = null),
                  ),
                  ...kRoleDisplayOrder.map(
                    (role) => _RoleChip(
                      label: role.displayName,
                      selected: _roleFilter == role,
                      color: role.color,
                      onTap: () => setState(
                        () => _roleFilter = _roleFilter == role ? null : role,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppTheme.md),
        if (_tab == 0)
          LegendStatsSection(legends: _displayedLegends, compact: widget.compact)
        else
          WeaponStatsSection(legendStats: widget.legendStats),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(40) : AppTheme.surface2,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppTheme.muted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _SegmentedCapsule extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  const _SegmentedCapsule({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(100),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.indexed.map((record) {
          final (index, option) = record;
          final isSelected = index == selected;
          return GestureDetector(
            onTap: () => onChanged(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.muted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
