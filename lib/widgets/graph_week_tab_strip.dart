import 'package:flutter/material.dart';
import '../utils/formatting/season_utils.dart';
import '../utils/theme.dart';

/// Horizontally-scrolling week chips (W1, W2, ...) for [GraphCard]'s week
/// selector. Auto-scrolls to keep the selected chip visible.
class WeekTabStrip extends StatefulWidget {
  final List<WeekRange> weeks;
  final int selectedIndex;
  final bool isCurrentSeason;
  final ValueChanged<int> onSelected;

  const WeekTabStrip({
    super.key,
    required this.weeks,
    required this.selectedIndex,
    required this.isCurrentSeason,
    required this.onSelected,
  });

  @override
  State<WeekTabStrip> createState() => _WeekTabStripState();
}

class _WeekTabStripState extends State<WeekTabStrip> {
  late ScrollController _scroll;

  // Approximate rendered width of each chip: label text (~28px) + horizontal
  // padding (8px each side) + inter-chip margin (2px) = ~46px.
  static const double _chipWidth = 46;
  // Scroll offset subtracted so the selected chip lands near the left edge
  // rather than at the very start of the viewport (~80px visible lead-in).
  static const double _chipScrollLeadIn = 80;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(WeekTabStrip old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) _scrollToSelected();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (!_scroll.hasClients) return;
    final offset =
        (widget.selectedIndex * _chipWidth - _chipScrollLeadIn).clamp(0.0, double.infinity);
    _scroll.animateTo(
      offset,
      duration: AppTheme.shortAnimation,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Center(
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.weeks.length, (i) {
            final week = widget.weeks[i];
            final isFuture =
                widget.isCurrentSeason && now.isBefore(week.start);
            final isSelected = i == widget.selectedIndex;

            return GestureDetector(
              onTap: isFuture ? null : () => widget.onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent
                      : isFuture
                          ? AppTheme.surface2.withAlpha(80)
                          : AppTheme.surface2,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'W${i + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : isFuture
                            ? AppTheme.muted.withAlpha(80)
                            : AppTheme.muted,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
