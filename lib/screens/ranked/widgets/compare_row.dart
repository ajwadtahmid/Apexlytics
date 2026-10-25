import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart'
    show formatSigned, formatSignedInt, plural;
import '../../../utils/theme.dart';

/// The colours of the first and second thing in a comparison, in its table and
/// its charts.
const kCompareColorA = AppTheme.muted;
const kCompareColorB = AppTheme.accent;

/// A colour swatch and a name, to say which side is which.
class CompareKey extends StatelessWidget {
  final Color color;
  final String name;
  const CompareKey({super.key, required this.color, required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption,
          ),
        ),
      ],
    );
  }
}

/// One row of a comparison table: a label, the two values and the change from
/// the first to the second, coloured good or bad. The better value is bold in a
/// chip tinted with its side's colour.
///
/// For a head-to-head where the first side is the reader (a player against
/// another), set [deltaFromFirst]: the change is then the first minus the
/// second, so a positive one means the first is ahead and reads green.
class CompareRow extends StatelessWidget {
  final String label;
  final String valueA;
  final String valueB;
  final double? delta;

  /// True when the delta is a whole count, shown without a decimal.
  final bool integerDelta;

  /// How many decimals the delta shows when it is not a whole count. A rate
  /// that moves in hundredths needs two to say anything.
  final int decimals;

  /// True for metrics where a higher value is worse (e.g. needing more games
  /// for the same result), so the delta's color reads opposite of the sign.
  final bool invert;

  /// True when [delta] is the first value minus the second, not the second
  /// minus the first.
  final bool deltaFromFirst;

  /// The tint of each side's leading chip. The defaults are the colours of the
  /// ranked Compare page.
  final Color colorA;
  final Color colorB;

  const CompareRow(
    this.label,
    this.valueA,
    this.valueB, {
    super.key,
    this.delta,
    this.integerDelta = false,
    this.decimals = 1,
    this.invert = false,
    this.deltaFromFirst = false,
    this.colorA = kCompareColorA,
    this.colorB = kCompareColorB,
  });

  /// Which side is ahead: -1 for the first, 1 for the second, 0 when they are
  /// level as shown or the row says nothing about better or worse.
  int get winner {
    final d = delta;
    if (d == null) return 0;
    final scale = math.pow(10, decimals);
    final shown = integerDelta ? d.round() : (d * scale).round() / scale;
    if (shown == 0) return 0;
    // Whether the side the change is measured towards is the one ahead.
    final towardsAhead = invert ? shown < 0 : shown > 0;
    if (deltaFromFirst) return towardsAhead ? -1 : 1;
    return towardsAhead ? 1 : -1;
  }

  String _deltaText(double d) {
    if (integerDelta) return formatSignedInt(d.round());
    if (decimals == 1) return formatSigned(d);
    final text = d.toStringAsFixed(decimals);
    // Nothing as shown reads as plain zero, never as a tiny negative.
    if (double.parse(text) == 0) return '+${0.0.toStringAsFixed(decimals)}';
    return d > 0 ? '+$text' : text;
  }

  // The label gets about a third of the row, the rest is shared by the values
  // and the change.
  static const _labelFlex = 7;
  static const _valueFlex = 5;
  static const _deltaFlex = 4;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final isGood = d == null ? null : (invert ? d < 0 : d >= 0);
    final lead = winner;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: _labelFlex,
            child: Text(label, style: AppTheme.caption),
          ),
          Expanded(
            flex: _valueFlex,
            child: _Value(valueA, color: colorA, leads: lead == -1),
          ),
          Expanded(
            flex: _valueFlex,
            child: _Value(valueB, color: colorB, leads: lead == 1),
          ),
          Expanded(
            flex: _deltaFlex,
            child: d == null
                ? const SizedBox()
                : Text(
                    _deltaText(d),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      // A change that is nothing as shown is neither good nor bad.
                      color: lead == 0
                          ? AppTheme.muted
                          : (isGood! ? AppTheme.green : AppTheme.red),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A value; the leading one is bold in a chip tinted with its side's [color].
class _Value extends StatelessWidget {
  final String text;
  final Color color;
  final bool leads;
  const _Value(this.text, {required this.color, required this.leads});

  @override
  Widget build(BuildContext context) {
    // Scales down rather than overflowing at large text sizes.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: leads ? color.withValues(alpha: 0.22) : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: leads ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// A comparison table: what the two colours are, which side leads on how many
/// of the rows, and the [rows].
class CompareTable extends StatelessWidget {
  final String nameA;
  final String nameB;
  final List<CompareRow> rows;

  /// True when the first side is the reader, so the line reads "You lead on".
  final bool firstIsYou;
  final Color colorA;
  final Color colorB;

  /// False for a second table under one that already shows which colour is
  /// which.
  final bool showKey;
  const CompareTable({
    super.key,
    required this.nameA,
    required this.nameB,
    required this.rows,
    this.firstIsYou = false,
    this.colorA = kCompareColorA,
    this.colorB = kCompareColorB,
    this.showKey = true,
  });

  @override
  Widget build(BuildContext context) {
    final a = rows.where((r) => r.winner == -1).length;
    final b = rows.where((r) => r.winner == 1).length;
    final decided = a + b;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showKey)
          Row(
            children: [
              Flexible(
                child: CompareKey(color: colorA, name: nameA),
              ),
              const SizedBox(width: AppTheme.md),
              Flexible(
                child: CompareKey(color: colorB, name: nameB),
              ),
            ],
          ),
        if (decided > 0) ...[
          const SizedBox(height: AppTheme.sm),
          Text(
            a == b
                ? 'Level: ${plural(a, 'stat')} each'
                : '${a > b ? nameA : nameB} '
                      '${a > b && firstIsYou ? 'lead' : 'leads'} on '
                      '${a > b ? a : b} of ${plural(decided, 'stat')}',
            style: TextStyle(
              // The leading side's colour, so it ties back to the key above. The
              // muted default would be hard to read as text, so it stays white.
              color: a == b
                  ? AppTheme.textPrimary
                  : a > b
                  ? (colorA == kCompareColorA ? AppTheme.textPrimary : colorA)
                  : colorB,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: AppTheme.xs),
        ...rows,
      ],
    );
  }
}
