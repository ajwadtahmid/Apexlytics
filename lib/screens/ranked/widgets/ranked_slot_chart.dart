import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart' show formatSigned, plural;
import '../../../utils/ranked/ranked_aggregates.dart' show kMinGamesForInsight;
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

/// Play by hour of day or day of week as bars, every hour or day in its own
/// column. A switch changes the bars between games played and RP per game.
///
/// With one period ([a] only), a bar is green where RP was gained and red where
/// it was lost. With a second ([b], and the two names), the bars are paired on
/// one axis so the periods line up, and under them goes where the best and
/// weakest hour or day moved.
///
/// In the RP per game view, a bar for an hour or day with under
/// [kMinGamesForInsight] games is faded, since a few games say little.
class RankedSlotChart extends StatefulWidget {
  final String title;

  /// "hour" or "day", for the summary lines.
  final String what;
  final String? nameA;
  final String? nameB;
  final List<Slot> a;
  final List<Slot>? b;

  /// The slots to chart, in order, one column each.
  final List<int> axis;
  final String Function(int slot) label;

  /// Whether the column at an index gets a label under it.
  final bool Function(int index) labelled;
  final double barWidth;

  const RankedSlotChart({
    super.key,
    required this.title,
    required this.what,
    this.nameA,
    this.nameB,
    required this.a,
    this.b,
    required this.axis,
    required this.label,
    required this.labelled,
    required this.barWidth,
  }) : assert(b == null || (nameA != null && nameB != null));

  /// Only the hours played, so a player who is never on at night doesn't get a
  /// blank stretch.
  factory RankedSlotChart.hours({
    Key? key,
    String? nameA,
    String? nameB,
    required List<Slot> a,
    List<Slot>? b,
  }) {
    final axis = hourAxis([...a, ...?b].map((s) => s.slot));
    final n = axis.length;
    // Wider bars when there are fewer columns to fit.
    final room = 280 / n - 3;
    return RankedSlotChart(
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
      barWidth: (b == null ? room : room / 2)
          .clamp(4, b == null ? 14 : 11)
          .toDouble(),
    );
  }

  factory RankedSlotChart.days({
    Key? key,
    String? nameA,
    String? nameB,
    required List<Slot> a,
    List<Slot>? b,
  }) => RankedSlotChart(
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
    barWidth: b == null ? 22 : 11,
  );

  @override
  State<RankedSlotChart> createState() => _RankedSlotChartState();
}

class _RankedSlotChartState extends State<RankedSlotChart> {
  bool _perGame = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final other = w.b;
    final paired = other != null;
    // One hour or day of play is no chart.
    if (paired ? w.a.isEmpty && other.isEmpty : w.a.length < 2) {
      return const SizedBox.shrink();
    }

    final byA = {for (final s in w.a) s.slot: s};
    final byB = {for (final s in other ?? const <Slot>[]) s.slot: s};
    final slots = w.axis;

    double value(Slot? s) => s == null || s.games == 0
        ? 0
        : (_perGame ? s.netRp / s.games : s.games.toDouble());
    final values = [
      for (final i in slots) ...[value(byA[i]), if (paired) value(byB[i])],
    ];
    final top = values.reduce((x, y) => x > y ? x : y);
    final bottom = values.reduce((x, y) => x < y ? x : y);
    final maxY = top <= 0 ? 1.0 : top * 1.25;
    final minY = _perGame && bottom < 0 ? bottom * 1.25 : 0.0;

    // Few games say little, so those bars are faded in the RP per game view.
    bool thin(Slot? s) => s != null && s.games < kMinGamesForInsight;
    final anyThin = _perGame && [...w.a, ...?other].any(thin);
    Color shade(Color c, Slot? s) =>
        _perGame && thin(s) ? c.withValues(alpha: 0.4) : c;
    Color side(Slot? s) =>
        s != null && s.netRp < 0 ? AppTheme.red : AppTheme.green;

    final verdicts = !paired
        ? const <String>[]
        : [
            for (final best in [true, false])
              slotVerdict(
                what: w.what,
                label: w.label,
                a: w.a,
                b: other,
                best: best,
              ),
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
          if (paired) ...[
            Row(
              children: [
                Flexible(
                  child: CompareKey(color: kCompareColorA, name: w.nameA!),
                ),
                const SizedBox(width: AppTheme.md),
                Flexible(
                  child: CompareKey(color: kCompareColorB, name: w.nameB!),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.md),
          ],
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
                      String line(String? name, Slot? s) {
                        final who = name == null ? '' : '$name: ';
                        return s == null
                            ? '${who}no games'
                            : '$who${plural(s.games, 'game')} · '
                                  '${formatSigned(s.netRp / s.games)} RP/game';
                      }

                      return BarTooltipItem(
                        '${w.label(slot)}\n'
                        '${line(w.nameA, byA[slot])}'
                        '${paired ? '\n${line(w.nameB, byB[slot])}' : ''}',
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
                          color: shade(
                            paired ? kCompareColorA : side(byA[slot]),
                            byA[slot],
                          ),
                          width: w.barWidth,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        if (paired)
                          BarChartRodData(
                            toY: value(byB[slot]),
                            color: shade(kCompareColorB, byB[slot]),
                            width: w.barWidth,
                            borderRadius: BorderRadius.circular(2),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (anyThin) ...[
            const SizedBox(height: AppTheme.sm),
            const Text(
              'Faded bars have under $kMinGamesForInsight games.',
              style: AppTheme.captionSmall,
            ),
          ],
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
