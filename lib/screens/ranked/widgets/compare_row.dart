import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart'
    show formatSigned, formatSignedInt;
import '../../../utils/theme.dart';

/// One row of a comparison table: a label, the two values and the change from
/// the first to the second, coloured good or bad.
class CompareRow extends StatelessWidget {
  final String label;
  final String valueA;
  final String valueB;
  final double? delta;

  /// True when the delta is a whole count, shown without a decimal.
  final bool integerDelta;

  /// True for metrics where a higher value is worse (e.g. needing more games
  /// for the same result), so the delta's color reads opposite of the sign.
  final bool invert;

  const CompareRow(
    this.label,
    this.valueA,
    this.valueB, {
    super.key,
    this.delta,
    this.integerDelta = false,
    this.invert = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final isGood = d == null ? null : (invert ? d < 0 : d >= 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: AppTheme.caption)),
          Expanded(
            child: Text(
              valueA,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valueB,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (d != null)
            Expanded(
              child: Text(
                integerDelta ? formatSignedInt(d.round()) : formatSigned(d),
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: isGood! ? AppTheme.green : AppTheme.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}
