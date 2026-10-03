import 'package:flutter/material.dart';
import '../utils/theme.dart';

class StatDisplay extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final bool compact;

  /// Overrides the value text's color (e.g. green/red for a signed RP figure)
  /// without changing the surrounding chip style. Takes precedence over
  /// [highlight] when set.
  final Color? valueColor;

  /// Centres the label and value instead of left-aligning them.
  final bool centered;

  const StatDisplay({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
    this.compact = false,
    this.valueColor,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = highlight ? AppTheme.accent : AppTheme.muted;
    final valueColor =
        this.valueColor ?? (highlight ? AppTheme.accent : AppTheme.textPrimary);
    final labelSize = compact ? 9.0 : 10.0;
    final valueSize = compact ? 12.0 : 15.0;
    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 7);

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: highlight ? AppTheme.accent.withAlpha(25) : AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: labelSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 3),
          // Scales down rather than wrapping or clipping on a huge value or
          // a large system font size.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: centered ? Alignment.center : Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: valueSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stat chips laid out as a two-column grid: each row in [rows] holds a pair
/// (e.g. per-game figure and its total) that split the width evenly, so every
/// chip is the same size and long values have half the row to fit in.
class StatGrid extends StatelessWidget {
  final List<List<Widget>> rows;
  const StatGrid({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppTheme.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < rows[i].length; j++) ...[
                  if (j > 0) const SizedBox(width: AppTheme.sm),
                  Expanded(child: rows[i][j]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One row of a [StatTable]: a [label] with its per-game [avg] and cumulative
/// [total] values, optionally tinted (e.g. green/red for RP).
class StatTableRow {
  final String label;
  final String avg;
  final String total;
  final Color? avgColor;
  final Color? totalColor;
  const StatTableRow({
    required this.label,
    required this.avg,
    required this.total,
    this.avgColor,
    this.totalColor,
  });
}

/// Compact Avg | Total table: one line per stat instead of a chip pair, so it
/// stays short and every value column lines up however big the numbers get.
class StatTable extends StatelessWidget {
  final List<StatTableRow> rows;
  const StatTable({super.key, required this.rows});

  static const _labelFlex = 2;
  static const _valueFlex = 3;

  Widget _headerCell(String text) => Expanded(
    flex: _valueFlex,
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: AppTheme.muted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _valueCell(String text, Color? color) => Expanded(
    flex: _valueFlex,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        text,
        style: TextStyle(
          color: color ?? AppTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.md,
        vertical: AppTheme.sm,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(flex: _labelFlex),
              _headerCell('AVERAGE'),
              _headerCell('TOTAL'),
            ],
          ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.sm),
              child: Row(
                children: [
                  Expanded(
                    flex: _labelFlex,
                    child: Text(
                      r.label,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _valueCell(r.avg, r.avgColor),
                  _valueCell(r.total, r.totalColor),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
