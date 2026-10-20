import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/stat_icons.dart';
import '../providers/best_metric_provider.dart';
import '../utils/ranked/best_metric.dart';
import '../utils/ranked/ranked_aggregates.dart' show kMinGamesForInsight;
import '../utils/theme.dart';
import 'choice_sheet.dart';
import 'control_pill.dart';

/// The colour for [value] under [metric]: green or red for RP, which is gained
/// or lost, and the app's accent for kills, damage and win rate, which can't be
/// negative and so are not good or bad news by their sign.
Color bestMetricColor(BestMetric metric, double value) =>
    metric.isRp ? AppTheme.signColor(value >= 0) : AppTheme.accent;

/// The icon each measure wears in the picker and on its pill: the one that
/// figure wears everywhere (see [StatIcons]).
IconData bestMetricIcon(BestMetric metric) => switch (metric) {
  BestMetric.totalRp => StatIcons.totalRp,
  BestMetric.rpPerGame => StatIcons.avgRp,
  BestMetric.winRate => StatIcons.winRate,
  BestMetric.avgKills => StatIcons.avgKills,
  BestMetric.totalKills => StatIcons.totalKills,
  BestMetric.avgDamage => StatIcons.avgDamage,
  BestMetric.totalDamage => StatIcons.totalDamage,
};

/// "Rank by: RP per game": what the strongest and weakest legends and maps are
/// judged on, with a tap to change it. The choice is shared (see
/// [bestMetricProvider]), so this reads the same wherever it is shown.
class BestMetricPill extends ConsumerWidget {
  const BestMetricPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metric = ref.watch(bestMetricProvider);
    return ControlPill(
      prefix: 'Rank by:',
      icon: bestMetricIcon(metric),
      label: metric.label,
      onTap: () => showBestMetricSheet(context, ref),
    );
  }
}

/// The sheet that picks the [BestMetric]. A choice applies at once and closes it.
Future<void> showBestMetricSheet(BuildContext context, WidgetRef ref) {
  return showChoiceSheet<BestMetric>(
    context,
    title: 'Rank legends and maps by',
    options: [
      for (final m in BestMetric.values)
        ChoiceOption(value: m, icon: bestMetricIcon(m), label: m.label),
    ],
    selected: ref.read(bestMetricProvider),
    onChosen: (m) => ref.read(bestMetricProvider.notifier).set(m),
    footnote:
        'Used for the strongest and weakest legends and maps on the Overview, '
        'the Recap, Legend × Map and Pick Rate, and for each session\'s top '
        'legend. A legend or map needs $kMinGamesForInsight or more games to '
        'count.',
  );
}
