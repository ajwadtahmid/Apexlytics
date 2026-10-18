import 'package:flutter/material.dart';
import '../constants/legend_constants.dart';
import '../models/player_stats.dart';
import '../utils/formatting/format.dart';
import '../utils/formatting/tracker_utils.dart';
import '../utils/theme.dart';
import '../utils/tracking/legend_calculations.dart';
import '../utils/tracking/legend_tracker_logic.dart';
import 'legend_header.dart';
import 'sheet_handle.dart';
import 'stat_display.dart';
import 'surface_card.dart';

final _brPrefixPattern = RegExp(r'^BR\s+');
final _killsSuffixPattern = RegExp(r'\s+kills$', caseSensitive: false);

/// Opens [legend]'s trackers as a bottom sheet: its header, the figures worked
/// out from the trackers, its favourite weapon types, and every tracker it has.
Future<void> showLegendTrackersSheet(BuildContext context, LegendStat legend) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => LegendTrackersSheet(legend: legend),
  );
}

/// The content of [showLegendTrackersSheet]. It is as tall as it needs to be and
/// scrolls when a legend has more than fits on the screen.
class LegendTrackersSheet extends StatelessWidget {
  final LegendStat legend;
  const LegendTrackersSheet({super.key, required this.legend});

  @override
  Widget build(BuildContext context) {
    final career = legend.name == kCareerLegendName;
    final trackers = deduplicateTrackers(legend.trackers);
    // The career entry has no Battle Royale figures to work out.
    final calculations = career
        ? const <LegendCalculation>[]
        : legendCalculations(legend.trackers);
    final weapons = career
        ? const <LegendTracker>[]
        : findTopWeaponCategories(legend.trackers);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: AppTheme.md),
              LegendHeader(name: legend.name),
              if (calculations.isNotEmpty) ...[
                const _Heading('Stats'),
                StatGrid(
                  rows: [
                    for (var i = 0; i < calculations.length; i += 2)
                      [
                        for (final c in calculations.skip(i).take(2))
                          StatDisplay(label: c.label, value: c.value),
                        // An odd one out keeps the width of the rest.
                        if (i + 1 >= calculations.length)
                          const SizedBox.shrink(),
                      ],
                  ],
                ),
              ],
              if (weapons.isNotEmpty) ...[
                const _Heading('Top Weapon Categories'),
                _WeaponRanks(weapons: weapons),
              ],
              if (trackers.isNotEmpty) ...[
                const _Heading('Trackers'),
                _ValueRows(
                  rows: [
                    for (final t in trackers)
                      (label: t.displayName, value: formatNumber(t.value)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.md, bottom: AppTheme.sm),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Rows of a muted label and a bold value, split by dividers.
class _ValueRows extends StatelessWidget {
  final List<({String label, String value})> rows;
  const _ValueRows({required this.rows});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              const Divider(color: AppTheme.surface2, height: 1, indent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.md,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.sm),
                  Text(
                    row.value,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The legend's top weapon types, numbered in medal colours.
class _WeaponRanks extends StatelessWidget {
  final List<LegendTracker> weapons;
  const _WeaponRanks({required this.weapons});

  static const _medals = [
    AppTheme.medalGold,
    AppTheme.medalSilver,
    AppTheme.medalBronze,
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          for (final (i, t) in weapons.indexed) ...[
            if (i > 0)
              const Divider(color: AppTheme.surface2, height: 1, indent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.md,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: _medals[i.clamp(0, _medals.length - 1)],
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: AppTheme.md),
                  Expanded(
                    child: Text(
                      t.displayName
                          .replaceFirst(_brPrefixPattern, '')
                          .replaceAll(_killsSuffixPattern, ''),
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    formatNumber(t.value),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
