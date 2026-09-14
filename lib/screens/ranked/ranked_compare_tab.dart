import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/season_meta.dart';
import '../../providers/ranked_provider.dart';
import '../../utils/formatting/format.dart'
    show formatNumber, formatSigned, formatSignedInt;
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/ranked/ranked_period.dart';
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';
import 'ranked_legend_map_matrix_screen.dart';
import 'widgets/ranked_day_of_week_chart.dart';
import 'widgets/ranked_squad_breakdown_card.dart';
import 'widgets/ranked_time_of_day_chart.dart';

/// Split-vs-split comparison. Embedded inline (not in its own scrollable) at
/// the bottom of the Personal Records screen, below the standout-game cards
/// and streak — the caller supplies the surrounding `ListView`.
///
/// Only real, named splits are selectable — not Lifetime (comparing "every
/// split combined" against one split isn't a split-vs-split comparison) and
/// not Unknown (a grab-bag of unclassified matches spanning an arbitrary
/// timeframe, not a coherent period).
///
/// Net RP is the only cross-split RP figure ever shown. A split's *current*
/// RP is never compared against another split's, because the ladder resets
/// between splits — diffing two absolute RP values across that boundary is
/// exactly the bug class documented in `extra/WEEKLY_RP_FIX_REPORT.md`.
class RankedCompareTab extends ConsumerStatefulWidget {
  final String uid;
  final List<RankedSplitBucket> splits;

  const RankedCompareTab({super.key, required this.uid, required this.splits});

  @override
  ConsumerState<RankedCompareTab> createState() => _RankedCompareTabState();
}

class _RankedCompareTabState extends ConsumerState<RankedCompareTab> {
  String? _splitAId;
  String? _splitBId;

  List<RankedSplitBucket> get _comparable => widget.splits
      .where((b) => b.id != kLifetimeSplitId && b.id != kUnknownSplitId)
      .toList();

  @override
  void initState() {
    super.initState();
    // B is "how am I doing now" and defaults to the current split; A is the
    // baseline being compared against and defaults to the one before it —
    // buckets already sort newest-first, so that's index 0 and 1.
    final real = _comparable;
    if (real.isNotEmpty) _splitBId = real[0].id;
    if (real.length > 1) _splitAId = real[1].id;
  }

  @override
  Widget build(BuildContext context) {
    final real = _comparable;
    if (real.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.lg),
        child: Center(
          child: Text(
            'Need at least two splits with recorded history to compare.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
        ),
      );
    }

    final idB = _splitBId ?? real[0].id;
    final idA = _splitAId ?? real[1].id;
    final bucketA = real.firstWhere((b) => b.id == idA, orElse: () => real[0]);
    final bucketB = real.firstWhere((b) => b.id == idB, orElse: () => real[1]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SplitPicker(
          splits: real,
          selectedA: bucketA.id,
          selectedB: bucketB.id,
          onChangedA: (id) => setState(() => _splitAId = id),
          onChangedB: (id) => setState(() => _splitBId = id),
        ),
        const SizedBox(height: AppTheme.md),
        _CompareBody(uid: widget.uid, bucketA: bucketA, bucketB: bucketB),
      ],
    );
  }
}

class _SplitPicker extends StatelessWidget {
  final List<RankedSplitBucket> splits;
  final String selectedA;
  final String selectedB;
  final ValueChanged<String> onChangedA;
  final ValueChanged<String> onChangedB;

  const _SplitPicker({
    required this.splits,
    required this.selectedA,
    required this.selectedB,
    required this.onChangedA,
    required this.onChangedB,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _LabeledDropdown(
            label: 'Comparing',
            splits: splits,
            value: selectedA,
            onChanged: onChangedA,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppTheme.sm),
          child: Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'vs',
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ),
        ),
        Expanded(
          child: _LabeledDropdown(
            label: 'Current',
            splits: splits,
            value: selectedB,
            onChanged: onChangedB,
          ),
        ),
      ],
    );
  }
}

class _LabeledDropdown extends StatelessWidget {
  final String label;
  final List<RankedSplitBucket> splits;
  final String value;
  final ValueChanged<String> onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.splits,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 2),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _SplitDropdown(splits: splits, value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SplitDropdown extends StatelessWidget {
  final List<RankedSplitBucket> splits;
  final String value;
  final ValueChanged<String> onChanged;

  const _SplitDropdown({
    required this.splits,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.sm),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.surface2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppTheme.surface,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          items: [
            for (final b in splits)
              DropdownMenuItem(
                value: b.id,
                child: Text(b.displayName, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id != null) onChanged(id);
          },
        ),
      ),
    );
  }
}

class _CompareBody extends ConsumerWidget {
  final String uid;
  final RankedSplitBucket bucketA;
  final RankedSplitBucket bucketB;

  const _CompareBody({
    required this.uid,
    required this.bucketA,
    required this.bucketB,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aAsync = ref.watch(
      rankedSplitDetailProvider((uid: uid, splitId: bucketA.id)),
    );
    final bAsync = ref.watch(
      rankedSplitDetailProvider((uid: uid, splitId: bucketB.id)),
    );

    if (aAsync.isLoading || bAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.lg),
        child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }
    final error = aAsync.error ?? bAsync.error;
    if (error != null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.lg),
        child: Center(
          child: Text(
            'Could not load one of these splits.',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
        ),
      );
    }
    final a = aAsync.requireValue;
    final b = bAsync.requireValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Disclaimer(),
        const SizedBox(height: AppTheme.md),
        _SummarySection(bucketA: bucketA, bucketB: bucketB, a: a, b: b),
        const SizedBox(height: AppTheme.md),
        const _SectionHeader('SQUAD'),
        _SplitLabel(bucketA.displayName),
        RankedSquadBreakdownCard(
          full: a.squadBreakdown.full,
          partial: a.squadBreakdown.partial,
        ),
        const SizedBox(height: AppTheme.sm),
        _SplitLabel(bucketB.displayName),
        RankedSquadBreakdownCard(
          full: b.squadBreakdown.full,
          partial: b.squadBreakdown.partial,
        ),
        const SizedBox(height: AppTheme.md),
        const _SectionHeader('PICK RATE'),
        _SplitLabel(bucketA.displayName),
        _PickRateList(legends: a.legends, totalGames: a.summary.games),
        const SizedBox(height: AppTheme.sm),
        _SplitLabel(bucketB.displayName),
        _PickRateList(legends: b.legends, totalGames: b.summary.games),
        const SizedBox(height: AppTheme.md),
        const _SectionHeader('LEGEND × MAP'),
        _SplitLabel(bucketA.displayName),
        SurfaceCard(
          padding: const EdgeInsets.all(AppTheme.md),
          child: RankedLegendMapMatrixView(cells: a.legendMap),
        ),
        const SizedBox(height: AppTheme.sm),
        _SplitLabel(bucketB.displayName),
        SurfaceCard(
          padding: const EdgeInsets.all(AppTheme.md),
          child: RankedLegendMapMatrixView(cells: b.legendMap),
        ),
        const SizedBox(height: AppTheme.md),
        const _SectionHeader('PERFORMANCE BY HOUR'),
        _SplitLabel(bucketA.displayName),
        RankedTimeOfDayChart(buckets: a.timeOfDay),
        const SizedBox(height: AppTheme.sm),
        _SplitLabel(bucketB.displayName),
        RankedTimeOfDayChart(buckets: b.timeOfDay),
        const SizedBox(height: AppTheme.md),
        const _SectionHeader('PERFORMANCE BY DAY'),
        _SplitLabel(bucketA.displayName),
        RankedDayOfWeekChart(buckets: a.dayOfWeek),
        const SizedBox(height: AppTheme.sm),
        _SplitLabel(bucketB.displayName),
        RankedDayOfWeekChart(buckets: b.dayOfWeek),
      ],
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppTheme.sm),
      child: Text(
        'Splits can differ in length, map rotation, and legend balance — treat '
        'differences as a starting point, not a verdict.',
        style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.sm),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SplitLabel extends StatelessWidget {
  final String text;
  const _SplitLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Elapsed days within [season] as of now, clamped to at least 1 so an
/// hours-old split doesn't divide by zero. Uses elapsed time, not the split's
/// full scheduled length, so an in-progress split isn't penalized for days it
/// hasn't reached yet.
int? _elapsedDays(SeasonMeta? season) {
  if (season == null) return null;
  final now = DateTime.now();
  final end = now.isBefore(season.end) ? now : season.end;
  final days = end.difference(season.start).inDays;
  return days < 1 ? 1 : days;
}

class _SummarySection extends StatelessWidget {
  final RankedSplitBucket bucketA;
  final RankedSplitBucket bucketB;
  final RankedSplitDetail a;
  final RankedSplitDetail b;

  const _SummarySection({
    required this.bucketA,
    required this.bucketB,
    required this.a,
    required this.b,
  });

  @override
  Widget build(BuildContext context) {
    final daysA = _elapsedDays(bucketA.season);
    final daysB = _elapsedDays(bucketB.season);
    final rpPerDayA = daysA == null ? null : a.summary.netRp / daysA;
    final rpPerDayB = daysB == null ? null : b.summary.netRp / daysB;
    final gamesPerDayA = daysA == null ? null : a.summary.games / daysA;
    final gamesPerDayB = daysB == null ? null : b.summary.games / daysB;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader('SUMMARY'),
          _Row(
            'Games',
            '${a.summary.games}',
            '${b.summary.games}',
            delta: (b.summary.games - a.summary.games).toDouble(),
            // Needing more games for a comparable result reads as worse, not
            // better, so this is the one row where "more" colors red.
            invert: true,
          ),
          _Row(
            'Games/day',
            gamesPerDayA == null ? '—' : gamesPerDayA.toStringAsFixed(1),
            gamesPerDayB == null ? '—' : gamesPerDayB.toStringAsFixed(1),
            delta: (gamesPerDayA != null && gamesPerDayB != null)
                ? gamesPerDayB - gamesPerDayA
                : null,
            invert: true,
          ),
          _Row(
            'Net RP',
            formatSignedInt(a.summary.netRp),
            formatSignedInt(b.summary.netRp),
            delta: (b.summary.netRp - a.summary.netRp).toDouble(),
          ),
          _Row(
            'RP/day',
            rpPerDayA == null ? '—' : formatSigned(rpPerDayA),
            rpPerDayB == null ? '—' : formatSigned(rpPerDayB),
            delta: (rpPerDayA != null && rpPerDayB != null)
                ? rpPerDayB - rpPerDayA
                : null,
          ),
          _Row(
            'Avg RP/game',
            formatSigned(a.summary.avgRpPerGame),
            formatSigned(b.summary.avgRpPerGame),
            delta: b.summary.avgRpPerGame - a.summary.avgRpPerGame,
          ),
          _Row(
            'Win rate',
            '${(a.summary.winRate * 100).toStringAsFixed(0)}%',
            '${(b.summary.winRate * 100).toStringAsFixed(0)}%',
            delta: (b.summary.winRate - a.summary.winRate) * 100,
          ),
          _Row(
            'Avg Kills',
            a.summary.avgKills.toStringAsFixed(1),
            b.summary.avgKills.toStringAsFixed(1),
            delta: b.summary.avgKills - a.summary.avgKills,
          ),
          _Row(
            'Avg Dmg',
            formatNumber(a.summary.avgDamage.round()),
            formatNumber(b.summary.avgDamage.round()),
            delta: b.summary.avgDamage - a.summary.avgDamage,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String valueA;
  final String valueB;
  final double? delta;

  /// True for metrics where a higher value is worse (e.g. needing more games
  /// for the same result), so the delta's color reads opposite of the sign.
  final bool invert;

  const _Row(
    this.label,
    this.valueA,
    this.valueB, {
    this.delta,
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
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
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
                '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)}',
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

class _PickRateList extends StatelessWidget {
  final List<LegendBreakdown> legends;
  final int totalGames;
  static const _kMaxShown = 6;

  const _PickRateList({required this.legends, required this.totalGames});

  @override
  Widget build(BuildContext context) {
    if (totalGames == 0 || legends.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.sm),
        child: Text(
          'No games',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      );
    }
    final sorted = [...legends]..sort((x, y) => y.games.compareTo(x.games));
    final shown = sorted.take(_kMaxShown).toList();

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.md,
        vertical: AppTheme.sm,
      ),
      child: Column(
        children: [
          for (final l in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.legend,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(l.games / totalGames * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                  const SizedBox(width: AppTheme.sm),
                  Text(
                    '${l.avgRpPerGame >= 0 ? '+' : ''}${l.avgRpPerGame.toStringAsFixed(1)} RP',
                    style: TextStyle(
                      color: l.avgRpPerGame >= 0
                          ? AppTheme.green
                          : AppTheme.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
