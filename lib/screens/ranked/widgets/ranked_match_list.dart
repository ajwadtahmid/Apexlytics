import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../constants/ranked_map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show formatNumber, timeAgo, formatDuration;
import '../../../utils/ranked/ranked_aggregates.dart' show kSessionGap;
import '../../../utils/theme.dart';
import '../../../widgets/legend_asset_image.dart';

/// History tab: every match in the selected period (ranked + casual), grouped by
/// day with session breaks. A mode filter scopes the list; tap a row for the
/// full match detail.
class RankedMatchList extends StatefulWidget {
  final List<RankedMatch> matches; // all-in-period, newest first
  final Future<void> Function() onRefresh;

  const RankedMatchList({
    super.key,
    required this.matches,
    required this.onRefresh,
  });

  @override
  State<RankedMatchList> createState() => _RankedMatchListState();
}

enum _Filter { all, ranked, casual }

class _RankedMatchListState extends State<RankedMatchList> {
  // Default to Ranked — it's the headline view; All/Casual are one tap away.
  _Filter _filter = _Filter.ranked;
  _HistorySort _sort = _HistorySort.date;

  List<RankedMatch> get _visible => switch (_filter) {
        _Filter.all => widget.matches,
        _Filter.ranked => widget.matches.where((m) => m.isRanked).toList(),
        _Filter.casual => widget.matches.where((m) => !m.isRanked).toList(),
      };

  MatchGrouping? get _grouping => switch (_sort) {
        _HistorySort.date => null,
        _HistorySort.legend => MatchGrouping(
            keyOf: (m) => m.legend,
            nameOf: (m) => m.legend,
          ),
        _HistorySort.map => MatchGrouping(
            keyOf: (m) => m.mapKey,
            nameOf: (m) => rankedMapName(m.mapKey),
          ),
      };

  @override
  Widget build(BuildContext context) {
    return MatchHistoryList(
      matches: _visible,
      onRefresh: widget.onRefresh,
      emptyLabel: 'No games in this filter',
      grouping: _grouping,
      header: _HistoryControls(
        filter: _filter,
        sort: _sort,
        onFilterTap: () => setState(() => _filter = _nextFilter(_filter)),
        onSortTap: () => setState(() => _sort = _nextSort(_sort)),
      ),
    );
  }
}

/// How to bucket matches when not grouping by day. [keyOf] decides which
/// section a match belongs to; [nameOf] is that section's display title.
class MatchGrouping {
  final String Function(RankedMatch) keyOf;
  final String Function(RankedMatch) nameOf;
  const MatchGrouping({required this.keyOf, required this.nameOf});
}

/// Day-grouped match list with session breaks and tap-through detail sheets.
/// Reused by the History tab (with a filter bar header) and the legend/map
/// drill-down screens (no header, pre-filtered list).
///
/// When [grouping] is supplied, matches are instead sectioned by that entity
/// (e.g. map within a legend), each section headed by its games/net-RP/avg-RP
/// summary and ordered by net RP descending. Day grouping is the default.
class MatchHistoryList extends StatelessWidget {
  final List<RankedMatch> matches; // newest first
  final Future<void> Function() onRefresh;

  /// Optional widget pinned above the scrolling list (e.g. the filter bar).
  final Widget? header;
  final String emptyLabel;

  /// Null → group by day (default). Set → group into entity sections.
  final MatchGrouping? grouping;

  const MatchHistoryList({
    super.key,
    required this.matches,
    required this.onRefresh,
    this.header,
    this.emptyLabel = 'No games yet',
    this.grouping,
  });

  @override
  Widget build(BuildContext context) {
    final g = grouping;
    final items = g == null ? _buildItems(matches) : _buildGrouped(matches, g);

    return Column(
      children: [
        ?header,
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: onRefresh,
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppTheme.xl),
                        child: Center(
                          child: Text(
                            emptyLabel,
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        AppTheme.md, AppTheme.sm, AppTheme.md, AppTheme.md),
                    itemCount: items.length,
                    itemBuilder: (_, i) => switch (items[i]) {
                      final _DayHeaderItem h => _DayHeader(item: h),
                      final _GroupHeaderItem h => _GroupHeader(item: h),
                      final _SessionBreakItem s => _SessionBreak(gapSecs: s.gapSecs),
                      final _MatchItem m => _MatchRow(match: m.match),
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// Flattens matches (newest first) into day headers, session breaks and rows.
  List<_HistoryItem> _buildItems(List<RankedMatch> matches) {
    final items = <_HistoryItem>[];
    DateTime? curDay;
    final dayBuckets = <List<RankedMatch>>[];
    for (final m in matches) {
      final lm = m.endTime.toLocal();
      final day = DateTime(lm.year, lm.month, lm.day);
      if (curDay == null || day != curDay) {
        dayBuckets.add(<RankedMatch>[]);
        curDay = day;
      }
      dayBuckets.last.add(m);
    }

    for (final bucket in dayBuckets) {
      final netRp = bucket.fold<int>(0, (a, m) => a + m.effectiveRpChange);
      final hasRanked = bucket.any((m) => m.isRanked);
      final day = bucket.first.endTime.toLocal();
      items.add(_DayHeaderItem(
        day: DateTime(day.year, day.month, day.day),
        netRp: netRp,
        hasRanked: hasRanked,
        games: bucket.length,
        isFirst: identical(bucket, dayBuckets.first),
      ));
      for (var i = 0; i < bucket.length; i++) {
        if (i > 0) {
          // newest-first: bucket[i-1] is later than bucket[i].
          final gap = bucket[i - 1].startTime.difference(bucket[i].endTime);
          if (gap > kSessionGap) {
            items.add(_SessionBreakItem(gap.inSeconds));
          }
        }
        items.add(_MatchItem(bucket[i]));
      }
    }
    return items;
  }

  /// Sections matches by [g], ordered by net (effective) RP descending, with
  /// matches newest-first inside each section. No session breaks in this mode.
  List<_HistoryItem> _buildGrouped(List<RankedMatch> matches, MatchGrouping g) {
    final byKey = <String, List<RankedMatch>>{};
    for (final m in matches) {
      byKey.putIfAbsent(g.keyOf(m), () => []).add(m);
    }

    final groups = byKey.values.map((ms) {
      final sorted = ms.toList()
        ..sort((a, b) => b.endTime.compareTo(a.endTime));
      final netRp = sorted.fold<int>(0, (a, m) => a + m.effectiveRpChange);
      return (name: g.nameOf(sorted.first), matches: sorted, netRp: netRp);
    }).toList()
      ..sort((a, b) => b.netRp.compareTo(a.netRp));

    final items = <_HistoryItem>[];
    for (final grp in groups) {
      items.add(_GroupHeaderItem(
        name: grp.name,
        games: grp.matches.length,
        netRp: grp.netRp,
        isFirst: identical(grp, groups.first),
      ));
      for (final m in grp.matches) {
        items.add(_MatchItem(m));
      }
    }
    return items;
  }
}

// ── Item model ──────────────────────────────────────────────────────────────

sealed class _HistoryItem {}

class _DayHeaderItem extends _HistoryItem {
  final DateTime day;
  final int netRp;
  final bool hasRanked;
  final int games;
  final bool isFirst;
  _DayHeaderItem(
      {required this.day,
      required this.netRp,
      required this.hasRanked,
      required this.games,
      required this.isFirst});
}

class _GroupHeaderItem extends _HistoryItem {
  final String name;
  final int games;
  final int netRp;
  final bool isFirst;
  _GroupHeaderItem(
      {required this.name,
      required this.games,
      required this.netRp,
      required this.isFirst});
}

class _SessionBreakItem extends _HistoryItem {
  final int gapSecs;
  _SessionBreakItem(this.gapSecs);
}

class _MatchItem extends _HistoryItem {
  final RankedMatch match;
  _MatchItem(this.match);
}

// ── Filter bar ──────────────────────────────────────────────────────────────

const _filterLabels = {
  _Filter.all: 'All',
  _Filter.ranked: 'Ranked',
  _Filter.casual: 'Casual',
};

const _filterIcons = {
  _Filter.all: Icons.filter_list,
  _Filter.ranked: Icons.military_tech,
  _Filter.casual: Icons.sports_esports,
};

// Cycle starts on Ranked (the default), then All, then Casual.
_Filter _nextFilter(_Filter f) => switch (f) {
  _Filter.ranked => _Filter.all,
  _Filter.all => _Filter.casual,
  _Filter.casual => _Filter.ranked,
};

enum _HistorySort { date, legend, map }

const _sortLabels = {
  _HistorySort.date: 'Date',
  _HistorySort.legend: 'Legend',
  _HistorySort.map: 'Map',
};

const _sortIcons = {
  _HistorySort.date: Icons.calendar_today,
  _HistorySort.legend: Icons.person_outline,
  _HistorySort.map: Icons.map_outlined,
};

_HistorySort _nextSort(_HistorySort s) => switch (s) {
  _HistorySort.date => _HistorySort.legend,
  _HistorySort.legend => _HistorySort.map,
  _HistorySort.map => _HistorySort.date,
};

/// History control strip: filter pill pinned left, sort pill pinned right.
/// Both cycle on tap, mirroring the Legends/Maps sort control's pill styling.
class _HistoryControls extends StatelessWidget {
  final _Filter filter;
  final _HistorySort sort;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;

  const _HistoryControls({
    required this.filter,
    required this.sort,
    required this.onFilterTap,
    required this.onSortTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.md, AppTheme.sm, AppTheme.md, AppTheme.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.surface2)),
      ),
      child: Row(
        children: [
          _ControlPill(
            prefix: 'Filter:',
            icon: _filterIcons[filter]!,
            label: _filterLabels[filter]!,
            onTap: onFilterTap,
          ),
          const Spacer(),
          _ControlPill(
            prefix: 'Sort:',
            icon: _sortIcons[sort]!,
            label: _sortLabels[sort]!,
            onTap: onSortTap,
          ),
        ],
      ),
    );
  }
}

/// A labelled, cycling pill: `prefix [icon value]`.
class _ControlPill extends StatelessWidget {
  final String prefix;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlPill({
    required this.prefix,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(prefix, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: AppTheme.accent),
                const SizedBox(width: 4),
                Text(
                  label,
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
    );
  }
}

// ── Day header ──────────────────────────────────────────────────────────────

String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEE, MMM d').format(day);
}

class _DayHeader extends StatelessWidget {
  final _DayHeaderItem item;
  const _DayHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    final positive = item.netRp >= 0;
    final color = positive ? AppTheme.green : AppTheme.red;
    return Column(
      children: [
        // Separate one day's session from the previous one.
        if (!item.isFirst)
          const Padding(
            padding: EdgeInsets.only(top: AppTheme.sm),
            child: Divider(color: AppTheme.surface2, height: 1, thickness: 1),
          ),
        Padding(
          padding: EdgeInsets.only(
              top: item.isFirst ? AppTheme.sm : AppTheme.md, bottom: 6),
          child: Row(
            children: [
              Text(
                _dayLabel(item.day),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: AppTheme.sm),
              Text(
                '${item.games} games',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const Spacer(),
              // Plain "Net ±RP" text (no pill) so the day total reads
              // differently from the per-match RP pills below it.
              if (item.hasRanked) ...[
                const Text(
                  'NET',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${positive ? '+' : ''}${formatNumber(item.netRp)} RP',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Group header (legend/map drill-down sections) ───────────────────────────

class _GroupHeader extends StatelessWidget {
  final _GroupHeaderItem item;
  const _GroupHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    final positive = item.netRp >= 0;
    final color = positive ? AppTheme.green : AppTheme.red;
    final avg = item.games == 0 ? 0.0 : item.netRp / item.games;
    return Column(
      children: [
        if (!item.isFirst)
          const Padding(
            padding: EdgeInsets.only(top: AppTheme.sm),
            child: Divider(color: AppTheme.surface2, height: 1, thickness: 1),
          ),
        Padding(
          padding: EdgeInsets.only(
              top: item.isFirst ? AppTheme.sm : AppTheme.md, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${item.games} games · ${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(1)} avg',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.sm),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Text(
                  '${positive ? '+' : ''}${formatNumber(item.netRp)} RP',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Session break ───────────────────────────────────────────────────────────

class _SessionBreak extends StatelessWidget {
  final int gapSecs;
  const _SessionBreak({required this.gapSecs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppTheme.surface2, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.sm),
            child: Text(
              '${formatDuration(gapSecs)} break',
              style: const TextStyle(color: AppTheme.muted, fontSize: 10),
            ),
          ),
          const Expanded(child: Divider(color: AppTheme.surface2, height: 1)),
        ],
      ),
    );
  }
}

// ── Match row ───────────────────────────────────────────────────────────────

String _legendImageKey(String legend) =>
    legend.toLowerCase().replaceAll(' ', '_');

class _MatchRow extends StatelessWidget {
  final RankedMatch match;
  const _MatchRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final ranked = match.isRanked;
    final up = match.rpChange >= 0;
    final rpColor = up ? AppTheme.green : AppTheme.red;

    return InkWell(
      onTap: () => _showDetail(context, match),
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: SizedBox(
                width: 36,
                height: 36,
                child: LegendAssetImage(
                  imageKey: _legendImageKey(match.legend),
                  displayName: match.legend,
                  fallbackFontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.legend,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${rankedMapName(match.mapKey)} · ${timeAgo(match.endTime)}',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (ranked)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (match.isRankedOutlier) ...[
                        const _OutlierTag(),
                        const SizedBox(width: 4),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: rpColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        ),
                        child: Text(
                          '${up ? '+' : ''}${match.rpChange} RP',
                          style: TextStyle(
                            color: rpColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  const _CasualTag(),
                const SizedBox(height: 2),
                Text(
                  '${match.kills} K · ${formatNumber(match.damage)} dmg',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, RankedMatch m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _MatchDetailSheet(match: m),
    );
  }
}

class _CasualTag extends StatelessWidget {
  const _CasualTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: const Text(
        'Casual',
        style: TextStyle(
          color: AppTheme.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Muted pill flagging a rank-reset RP swing. Matches the RP pill's shape but
/// stays neutral, signalling the value is excluded from every RP aggregate.
class _OutlierTag extends StatelessWidget {
  const _OutlierTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: const Text(
        'Outlier',
        style: TextStyle(
          color: AppTheme.muted,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Detail sheet ────────────────────────────────────────────────────────────

class _MatchDetailSheet extends StatelessWidget {
  final RankedMatch match;
  const _MatchDetailSheet({required this.match});

  static final _fmt = DateFormat('MMM d, yyyy · h:mm a');

  @override
  Widget build(BuildContext context) {
    final ranked = match.isRanked;
    final up = match.rpChange >= 0;
    final rpColor = up ? AppTheme.green : AppTheme.red;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  match.legend,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                _ModeChip(ranked: ranked),
              ],
            ),
            const SizedBox(height: AppTheme.sm),
            // RP block (ranked only) with tier badge.
            if (ranked) ...[
              Row(
                children: [
                  if (match.rankImg.isNotEmpty) ...[
                    CachedNetworkImage(
                      imageUrl: match.rankImg,
                      width: 34,
                      height: 34,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) => const SizedBox(width: 34),
                    ),
                    const SizedBox(width: AppTheme.sm),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ranked Points',
                          style:
                              TextStyle(color: AppTheme.muted, fontSize: 11)),
                      Text(
                        formatNumber(match.cumulativeRp),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${up ? '+' : ''}${match.rpChange} RP',
                    style: TextStyle(
                      color: rpColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (match.isRankedOutlier) ...[
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 13, color: AppTheme.muted),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Outlier Ranked Points: excluded from all calculation',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppTheme.sm),
            ],
            // Meta line.
            Text(
              '${rankedMapName(match.mapKey)} · ${_fmt.format(match.endTime.toLocal())}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              '${(match.lengthSecs / 60).round()}m · ${match.isPartyFull ? 'Full squad' : 'Partial squad'}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: AppTheme.md),
            const Divider(color: AppTheme.surface2, height: 1),
            const SizedBox(height: AppTheme.md),
            if (match.trackers.isEmpty)
              const Text(
                'No tracker data for this match',
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              )
            else
              ...match.trackers.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          t.name,
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: AppTheme.sm),
                      Text(
                        formatNumber(t.value.toInt()),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final bool ranked;
  const _ModeChip({required this.ranked});

  @override
  Widget build(BuildContext context) {
    final color = ranked ? AppTheme.accent : AppTheme.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        ranked ? 'Ranked' : 'Casual',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
