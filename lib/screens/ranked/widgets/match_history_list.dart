import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../providers/history_collapse_provider.dart';
import '../../../utils/formatting/format.dart'
    show calendarDaysBetween, formatNumber, timeAgo, formatDuration;
import '../../../utils/theme.dart';
import '../../../widgets/legend_asset_image.dart';
import 'match_detail_sheet.dart';
import 'match_history_items.dart';
import 'match_tags.dart';

/// Day-grouped match list with session breaks and tap-through detail sheets.
/// Reused by the History tab (with a filter bar header) and the legend/map
/// drill-down screens (no header, pre-filtered list).
///
/// Each day (or entity section) has a header that pins to the top while its
/// matches scroll underneath; a day header also collapses its matches on tap.
///
/// When [grouping] is supplied, matches are instead sectioned by that entity
/// (e.g. map within a legend), each section headed by its games/net-RP/avg-RP
/// summary and ordered by net RP descending. Day grouping is the default.
///
/// Day-grouped mode paginates in increments of [kHistoryPageSize], loading the
/// next page automatically as the user scrolls near the bottom, extended to a
/// day boundary (see [buildDayItems]) — grouped mode shows everything,
/// since it's already a filtered, RP-sorted subset rather than a long
/// chronological feed.
class MatchHistoryList extends ConsumerStatefulWidget {
  final List<RankedMatch> matches; // newest first
  final Future<void> Function() onRefresh;

  /// Optional widget pinned above the scrolling list (e.g. the filter bar).
  final Widget? header;
  final String emptyLabel;

  /// Null → group by day (default). Set → group into entity sections.
  final MatchGrouping? grouping;

  /// Called when a row's detail sheet saves or clears a correction. Callers
  /// backed by a reactive provider (the History tab) can leave this unset —
  /// invalidation already refreshes [matches]. Callers holding a static list
  /// (e.g. a legend/map drill-down screen) should use it to patch their own
  /// copy so the edit is visible without leaving the page.
  final ValueChanged<RankedMatch>? onMatchUpdated;

  /// Matches the detail sheet averages a legend over, to show how a game
  /// compares. Null hides the comparison — right for a list that doesn't hold
  /// the legend's whole history (e.g. one map's games).
  final List<RankedMatch>? averagePool;

  /// Names this list when remembering collapsed days, so the same date
  /// collapsed here doesn't also collapse in another list.
  final String collapseScope;

  const MatchHistoryList({
    super.key,
    required this.matches,
    required this.onRefresh,
    this.header,
    this.emptyLabel = 'No games yet',
    this.grouping,
    this.onMatchUpdated,
    this.averagePool,
    this.collapseScope = 'history',
  });

  @override
  ConsumerState<MatchHistoryList> createState() => _MatchHistoryListState();
}

// Start auto-loading the next page once the user scrolls within this many
// pixels of the bottom, so the next batch is ready before they hit the edge.
const double _kLoadMoreThreshold = 400;

/// A pinned header and the rows beneath it.
class _Section {
  final HistoryItem header;
  final List<HistoryItem> body = [];
  _Section(this.header);
}

class _MatchHistoryListState extends ConsumerState<MatchHistoryList> {
  int _pageLimit = kHistoryPageSize;
  final _scrollController = ScrollController();

  // Flattened list, rebuilt only when matches, page limit or grouping change.
  List<RankedMatch>? _builtFrom;
  int _builtLimit = -1;
  MatchGrouping? _builtGrouping;
  List<_Section> _sections = const [];
  List<RankedMatch> _ordered = const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(MatchHistoryList old) {
    super.didUpdateWidget(old);
    // A genuinely different match set (filter/sort change, not just an
    // incidental rebuild from a periodic background refetch) starts back at
    // page one rather than showing a stale scroll depth. Compared by length +
    // newest key rather than list identity, since callers rebuild a fresh
    // `List` on every build even when the underlying data is unchanged.
    if (widget.matches.length != old.matches.length ||
        _headKey(widget.matches) != _headKey(old.matches) ||
        widget.grouping != old.grouping) {
      _pageLimit = kHistoryPageSize;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  String? _headKey(List<RankedMatch> matches) =>
      matches.isEmpty ? null : matches.first.id;

  void _onScroll() => _loadMoreIfNeeded();

  /// Loads the next page near the end of the list. Also run after each build: a list too
  /// short to scroll never fires a scroll event.
  void _loadMoreIfNeeded() {
    if (!mounted || widget.grouping != null) return; // day-mode only
    if (_pageLimit >= widget.matches.length) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _kLoadMoreThreshold) {
      setState(() => _pageLimit += kHistoryPageSize);
    }
  }

  /// Splits the flat item list into header-led sections. Both builders open
  /// every section with its header, so nothing precedes the first one.
  List<_Section> _sectionsOf(List<HistoryItem> items) {
    final sections = <_Section>[];
    for (final item in items) {
      if (item is DayHeaderItem || item is GroupHeaderItem) {
        sections.add(_Section(item));
      } else if (sections.isNotEmpty) {
        sections.last.body.add(item);
      }
    }
    return sections;
  }

  Future<void> _openDetail(List<RankedMatch> ordered, RankedMatch m) async {
    final i = ordered.indexWhere((x) => x.id == m.id);
    if (i < 0) return;
    final updated = await showMatchDetailSheet(
      context,
      matches: ordered,
      index: i,
      baselinePool: widget.averagePool,
    );
    if (updated != null) widget.onMatchUpdated?.call(updated);
  }

  /// Rebuilds [_sections] and [_ordered] only if matches (by identity), limit or grouping changed.
  void _refreshItems() {
    final g = widget.grouping;
    if (identical(_builtFrom, widget.matches) &&
        _builtLimit == _pageLimit &&
        identical(_builtGrouping, g)) {
      return;
    }
    final items = g == null
        ? buildDayItems(widget.matches, limit: _pageLimit)
        : buildGroupedItems(widget.matches, g);
    _sections = _sectionsOf(items);
    // What prev/next in the detail sheet walks: the full list in display
    // order, not just the page currently rendered.
    _ordered = g == null
        ? widget.matches
        : [
            for (final item in items)
              if (item is MatchItem) item.match,
          ];
    _builtFrom = widget.matches;
    _builtLimit = _pageLimit;
    _builtGrouping = g;
  }

  @override
  Widget build(BuildContext context) {
    _refreshItems();
    final sections = _sections;
    // After layout; each page loaded rebuilds and re-checks until the viewport is full.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMoreIfNeeded());

    return Column(
      children: [
        ?widget.header,
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: widget.onRefresh,
            child: sections.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppTheme.xl),
                        child: Center(
                          child: Text(
                            widget.emptyLabel,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.md,
                          0,
                          AppTheme.md,
                          AppTheme.md,
                        ),
                        sliver: SliverMainAxisGroup(
                          slivers: [
                            for (final section in sections)
                              _SectionSliver(
                                section: section,
                                collapseScope: widget.collapseScope,
                                ordered: _ordered,
                                onOpen: _openDetail,
                              ),
                          ],
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

/// A header and its rows; watches only its own day's collapsed state.
class _SectionSliver extends ConsumerWidget {
  final _Section section;
  final String collapseScope;
  final List<RankedMatch> ordered;
  final Future<void> Function(List<RankedMatch> ordered, RankedMatch m) onOpen;

  const _SectionSliver({
    required this.section,
    required this.collapseScope,
    required this.ordered,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = section.header;
    final dayKey = header is DayHeaderItem
        ? historyDayKey(collapseScope, header.day)
        : null;
    final isCollapsed =
        dayKey != null &&
        ref.watch(
          collapsedHistoryDaysProvider.select((days) => days.contains(dayKey)),
        );

    final Widget headerWidget = switch (header) {
      final DayHeaderItem h => _DayTitle(
        item: h,
        collapsed: isCollapsed,
        onToggle: () =>
            ref.read(collapsedHistoryDaysProvider.notifier).toggle(dayKey!),
      ),
      final GroupHeaderItem h => _GroupHeader(item: h),
      _ => const SizedBox.shrink(),
    };

    return SliverMainAxisGroup(
      slivers: [
        // Opaque so rows scrolling underneath don't show through the pin.
        PinnedHeaderSliver(
          child: ColoredBox(color: AppTheme.bg, child: headerWidget),
        ),
        // The labelled stats scroll with the day rather than pinning.
        if (header is DayHeaderItem)
          SliverToBoxAdapter(
            child: _DayStats(item: header, collapsed: isCollapsed),
          ),
        if (!isCollapsed)
          SliverList.builder(
            itemCount: section.body.length,
            itemBuilder: (_, i) => switch (section.body[i]) {
              final SessionBreakItem s => _SessionBreak(gapSecs: s.gapSecs),
              final MatchItem m => _MatchRow(
                match: m.match,
                onTap: () => onOpen(ordered, m.match),
              ),
              _ => const SizedBox.shrink(),
            },
          ),
      ],
    );
  }
}

// ── Day header ──────────────────────────────────────────────────────────────

final _dayFmt = DateFormat('EEE, MMM d');

String _dayLabel(DateTime day) {
  final diff = calendarDaysBetween(DateTime.now(), day);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return _dayFmt.format(day);
}

/// A day's title row: collapse chevron, the day, "N games · time played", and
/// the day's net RP as a pill that matches the per-match RP badges below.
///
/// This is the only part of a day's header that pins while scrolling; the
/// labelled stats ([_DayStats]) scroll away with the day, so the pinned bar
/// stays small and calm. Tapping it collapses or expands the day's matches.
class _DayTitle extends StatelessWidget {
  final DayHeaderItem item;
  final bool collapsed;
  final VoidCallback onToggle;
  const _DayTitle({
    required this.item,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final positive = item.netRp >= 0;
    final color = AppTheme.signColor(positive);
    final played = item.playSecs > 0
        ? ' · ${formatDuration(item.playSecs)}'
        : '';

    return Column(
      children: [
        // Separate one day's session from the previous one.
        if (!item.isFirst)
          const Padding(
            padding: EdgeInsets.only(top: AppTheme.sm),
            child: Divider(color: AppTheme.surface2, height: 1, thickness: 1),
          ),
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: EdgeInsets.only(
              top: item.isFirst ? AppTheme.sm : AppTheme.md,
              bottom: 6,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: collapsed ? -0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(
                    Icons.expand_more,
                    size: 18,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  _dayLabel(item.day),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Expanded(
                  child: Text(
                    '${item.games} games$played',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (item.hasRanked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
        ),
      ],
    );
  }
}

/// The day's numbers as equal columns, each a value over a small label, so
/// they line up from day to day and read without decoding abbreviations:
/// record, average RP, kills and damage (record and average only on days with
/// ranked games). Collapsed, only the record remains.
class _DayStats extends StatelessWidget {
  final DayHeaderItem item;
  final bool collapsed;
  const _DayStats({required this.item, required this.collapsed});

  /// Aligns under the day name, past the chevron.
  static const _indent = 20.0;

  static const _value = TextStyle(
    color: AppTheme.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  TextSpan get _record => TextSpan(
    style: _value,
    children: [
      TextSpan(
        text: '${item.wins}W',
        style: const TextStyle(color: AppTheme.green),
      ),
      const TextSpan(text: '–'),
      TextSpan(
        text: '${item.losses}L',
        style: const TextStyle(color: AppTheme.red),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      if (!item.hasRanked) return const SizedBox(height: 4);
      return Padding(
        padding: const EdgeInsets.only(left: _indent, bottom: 8),
        child: Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            children: _record.children,
          ),
        ),
      );
    }

    final avg = item.avgRp;
    return Padding(
      padding: const EdgeInsets.only(left: _indent, bottom: AppTheme.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.hasRanked) _stat('Record', _record),
          if (item.hasRanked && avg != null)
            _stat(
              'Avg RP',
              TextSpan(
                text: '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(1)}',
                style: _value,
              ),
            ),
          _stat(
            'Kills',
            TextSpan(text: formatNumber(item.kills), style: _value),
          ),
          _stat(
            'Damage',
            TextSpan(text: formatNumber(item.damage), style: _value),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, TextSpan value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 11),
        ),
      ],
    ),
  );
}

// ── Group header (legend/map drill-down sections) ───────────────────────────

class _GroupHeader extends StatelessWidget {
  final GroupHeaderItem item;
  const _GroupHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    final positive = item.netRp >= 0;
    final color = AppTheme.signColor(positive);
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
            top: item.isFirst ? AppTheme.sm : AppTheme.md,
            bottom: 6,
          ),
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
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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

class _MatchRow extends StatelessWidget {
  final RankedMatch match;
  final VoidCallback onTap;
  const _MatchRow({required this.match, required this.onTap});

  static Widget _tagged(List<MatchTagNote> notes, Widget child) {
    if (notes.isEmpty) return child;
    return Tooltip(
      message: [for (final n in notes) '${n.label}: ${n.text}'].join('\n'),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ranked = match.isRanked;
    final up = match.rpChange >= 0;
    final rpColor = AppTheme.signColor(up);
    final notes = matchTagNotes(match);

    final tagRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!match.countsTowardStats) ...[
          const ExcludedTag(),
          const SizedBox(width: 4),
        ],
        if (ranked)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          )
        else
          const CasualTag(),
      ],
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Opacity(
        opacity: match.countsTowardStats ? 1 : 0.45,
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
                    imageKey: legendImageKey(match.legend),
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
                      '${battleRoyaleMapName(match.mapKey)} · ${timeAgo(match.endTime)}',
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Long-press explains the flags; the row's tap still opens the
              // sheet, which spells them out too.
              _tagged(
                notes,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    tagRow,
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (match.isEdited) ...[
                          const EditedTag(),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          // An em dash marks a stat upstream never reported,
                          // which is not the same as a scoreless game.
                          '${match.kills ?? '—'} K · '
                          '${match.damage == null ? '—' : formatNumber(match.damage!)} dmg',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
