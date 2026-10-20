import 'package:flutter/material.dart';
import '../utils/formatting/format.dart' show formatSigned, formatSignedInt;
import '../utils/theme.dart';

/// RP gained/lost pill — a tinted (not solid) background so it reads as a
/// plain-card chip rather than the dark-scrim [MapRpBadge] meant to sit over
/// map artwork. Shows a total (`+1,234 RP`) or, via [RpPill.perGame], an
/// average per game (`+12.4 /game`).
///
/// [RpPill.custom] is the same chip for any other figure, in a colour of the
/// caller's choosing (kills and damage are not gains or losses).
///
/// [compact] is the smaller form for dense rows (a day header, a single
/// match): less padding and a 12 pt label.
class RpPill extends StatelessWidget {
  final int? totalRp;
  final double? avgRp;
  final String? text;
  final Color? color;
  final bool compact;
  const RpPill({super.key, required int this.totalRp, this.compact = false})
    : avgRp = null,
      text = null,
      color = null;
  const RpPill.perGame({
    super.key,
    required double this.avgRp,
    this.compact = false,
  }) : totalRp = null,
       text = null,
       color = null;
  const RpPill.custom({
    super.key,
    required String this.text,
    required Color this.color,
    this.compact = false,
  }) : totalRp = null,
       avgRp = null;

  @override
  Widget build(BuildContext context) {
    final avg = avgRp;
    final shown =
        text ??
        (avg != null
            ? '${formatSigned(avg)} /game'
            : '${formatSignedInt(totalRp!)} RP');
    final color =
        this.color ??
        AppTheme.signColor(avg != null ? avg >= 0 : totalRp! >= 0);
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: AppTheme.sm, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: AppTheme.xs),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        shown,
        style: TextStyle(
          color: color,
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
