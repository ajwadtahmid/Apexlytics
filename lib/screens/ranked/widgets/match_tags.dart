import 'package:flutter/material.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart' show formatSignedInt;
import '../../../utils/theme.dart';

/// Pill for a mode or state flag on a match, in the muted/accent family.
class _TagPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color? background;
  final double fontSize;
  final FontWeight weight;
  final EdgeInsets padding;
  const _TagPill({
    required this.text,
    required this.color,
    this.background,
    this.fontSize = 12,
    this.weight = FontWeight.bold,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
      ),
    );
  }
}

class CasualTag extends StatelessWidget {
  const CasualTag({super.key});

  @override
  Widget build(BuildContext context) => const _TagPill(
    text: 'Casual',
    color: AppTheme.muted,
    fontSize: 11,
    weight: FontWeight.w600,
  );
}

/// Muted pill flagging a match that is left out of the stats — hand-excluded,
/// or excluded automatically for an implausible RP swing. Its row still shows
/// (greyed) but every stat/breakdown/trend skips it.
class ExcludedTag extends StatelessWidget {
  const ExcludedTag({super.key});

  @override
  Widget build(BuildContext context) =>
      const _TagPill(text: 'Excluded', color: AppTheme.muted);
}

/// Marks a match carrying at least one hand-corrected stat.
class EditedChip extends StatelessWidget {
  const EditedChip({super.key});

  @override
  Widget build(BuildContext context) => _TagPill(
    text: 'Edited',
    color: AppTheme.accent,
    background: AppTheme.accent.withAlpha(30),
    fontSize: 11,
    weight: FontWeight.w600,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  );
}

/// Muted "Edited" pill for a match row, in the family of [ExcludedTag];
/// sized to sit beside the row's kills/damage line.
class EditedTag extends StatelessWidget {
  const EditedTag({super.key});

  @override
  Widget build(BuildContext context) => const _TagPill(
    text: 'Edited',
    color: AppTheme.muted,
    fontSize: 11,
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
  );
}

class MatchModeChip extends StatelessWidget {
  final bool ranked;
  const MatchModeChip({super.key, required this.ranked});

  @override
  Widget build(BuildContext context) {
    final color = ranked ? AppTheme.accent : AppTheme.muted;
    return _TagPill(
      text: ranked ? 'Ranked' : 'Casual',
      color: color,
      background: color.withAlpha(30),
      fontSize: 11,
      weight: FontWeight.w600,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    );
  }
}

/// One flag on a match with a one-line explanation, shown in a row's tooltip
/// and listed in the detail sheet.
class MatchTagNote {
  final String label;
  final String text;
  const MatchTagNote(this.label, this.text);
}

const _fieldLabels = {
  'legend': 'legend',
  'map_key': 'map',
  'rp_change': 'RP',
  'kills': 'kills',
  'damage': 'damage',
};

/// Every state flag on [m] (excluded, edited), most important first. Both kinds
/// of exclusion read as "Excluded"; the text says which it was.
List<MatchTagNote> matchTagNotes(RankedMatch m) {
  return [
    if (m.excluded)
      const MatchTagNote(
        'Excluded',
        'Left out of every stat, trend and total.',
      )
    else if (m.isAutoExcluded)
      MatchTagNote(
        'Excluded',
        'Excluded automatically: its RP change (${formatSignedInt(m.rpChange)}) '
            'is outside the normal range. Correct the RP to include it.',
      ),
    if (m.isEdited)
      MatchTagNote(
        'Edited',
        'Corrected by hand: ${(m.editedFields.map((f) => _fieldLabels[f] ?? f).toList()..sort()).join(', ')}.',
      ),
  ];
}
