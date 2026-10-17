import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart' show formatSigned, plural;
import '../../../utils/ranked/slot_compare.dart';
import '../../../utils/theme.dart';
import '../../../widgets/segmented_capsule.dart';
import '../../../widgets/surface_card.dart';
import 'compare_row.dart';

String _hourLabel(int hour) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h ${hour < 12 ? 'AM' : 'PM'}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Two periods' play by hour of day or day of week as paired bars on one axis,
/// every hour or day in its own column so the two line up. A switch changes
/// the bars between games played and RP per game; under them, where the best
/// and weakest hour or day went.
class RankedSlotCompareChart extends StatefulWidget {
  final String title;

  /// "hour" or "day", for the summary lines.
  final String what;
  final String nameA;
  final String nameB;
  final List<Slot> a;
  final List<Slot> b;

  /// The slots to chart, in order, one column each.
  final List<int> axis;
  final String Function(int slot) label;

  /// Whether the column at an index gets a label under it.
  final bool Function(int index) labelled;
  final double barWidth;

  const RankedSlotCompareChart({
    super.key,
    required this.title,
    required this.what,
    required this.nameA,
    required this.nameB,
    required this.a,
    required this.b,
    required this.axis,
    required this.label,
    required this.labelled,
    required this.barWidth,
  });

  /// Only the hours either period played, so a player who is never on at night
  /// doesn't get a blank stretch.
  factory RankedSlotCompareChart.hours({
    Key? key,
    required String nameA,
    required String nameB,
    required List<Slot> a,
    required List<Slot> b,
  }) {
    final axis = hourAxis([...a, ...b].map((s) => s.slot));
    final n = axis.length;
    return RankedSlotCompareChart(
      key: key,
      title: 'Performance by Hour',
      what: 'hour',
      nameA: nameA,
      nameB: nameB,
      a: a,
      b: b,
      axis: axis,
      label: _hourLabel,
      labelled: (i) => i % (n > 12 ? 3 : (n > 6 ? 2 : 1)) == 0,
      // Wider bars when there are fewer columns to fit.
      barWidth: ((280 / n - 3) / 2).clamp(4, 11).toDouble(),
    );
  }

  factory RankedSlotCompareChart.days({
    Key? key,
    required String nameA,
    required String nameB,
    required List<Slot> a,
    required List<Slot> b,
  }) => RankedSlotCompareChart(
    key: key,
    title: 'Performance by Day',
    what: 'day',
    nameA: nameA,
    nameB: nameB,
    a: a,
    b: b,
    axis: const [1, 2, 3, 4, 5, 6, 7],
    label: (d) => _weekdays[d - 1],
    labelled: (_) => true,
    barWidth: 11,
  );

  @override
  State<RankedSlotCompareChart> createState() => _RankedSlotCompareChartState();
}

class _RankedSlotCompareChartState extends State<RankedSlotCompareChart> {
  bool _perGame = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    if (w.a.isEmpty && w.b.isEmpty) return const SizedBox.shrink();

    final byA = {for (final s in w.a) s.slot: s};
    final byB = {for (final s in w.b) s.slot: s};
    final slots = w.axis;

    double value(Slot? s) => s == null || s.games == 0
        ? 0
        : (_perGame ? s.netRp / s.games : s.games.toDouble());
    final values = [
      for (final i in slots) ...[value(byA[i]), value(byB[i])],
    ];
    final top = values.reduce((x, y) => x > y ? x : y);
    final bottom = values.reduce((x, y) => x < y ? x : y);
    final maxY = top <= 0 ? 1.0 : top * 1.25;
    final minY = _perGame && bottom < 0 ? bottom * 1.25 : 0.0;

    final verdicts = [
      for (final best in [true, false])
        slotVerdict(what: w.what, label: w.label, a: w.a, b: w.b, best: best),
    ].whereType<String>().toList();

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(w.title, style: AppTheme.cardTitle),
          const SizedBox(height: AppTheme.sm),
          Center(
            child: SegmentedCapsule(
              options: const ['Games', 'RP / game'],
              selected: _perGame ? 1 : 0,
              onChanged: (i) => setState(() => _perGame = i == 1),
            ),
          ),
          const SizedBox(height: AppTheme.md),
          Row(
            children: [
              Flexible(
                child: CompareKey(color: kCompareColorA, name: w.nameA),
              ),
              const SizedBox(width: AppTheme.md),
              Flexible(
                child: CompareKey(color: kCompareColorB, name: w.nameB),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.md),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                minY: minY,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.surface2,
                    getTooltipItem: (group, _, rod, _) {
                      final slot = slots[group.x];
                      String line(String name, Slot? s) => s == null
                          ? '$name: no games'
                          : '$name: ${plural(s.games, 'game')} · '
                                '${formatSigned(s.netRp / s.games)} RP/game';
                      return BarTooltipItem(
                        '${w.label(slot)}\n'
                        '${line(w.nameA, byA[slot])}\n'
                        '${line(w.nameB, byB[slot])}',
                        const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: 1,
                      getTitlesWidget: (x, _) {
                        final i = x.toInt();
                        if (i < 0 || i >= slots.length || !w.labelled(i)) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: AppTheme.xs),
                          child: Text(
                            w.label(slots[i]),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 9,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (final (i, slot) in slots.indexed)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 1,
                      barRods: [
                        BarChartRodData(
                          toY: value(byA[slot]),
                          color: kCompareColorA,
                          width: w.barWidth,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: value(byB[slot]),
                          color: kCompareColorB,
                          width: w.barWidth,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (verdicts.isNotEmpty) ...[
            const SizedBox(height: AppTheme.md),
            for (final v in verdicts)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(v, style: AppTheme.captionLarge),
              ),
          ],
        ],
      ),
    );
  }
}
