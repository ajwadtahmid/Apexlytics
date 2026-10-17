import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ranked_match.dart';
import '../../models/season_meta.dart';
import '../../providers/ranked_provider.dart';
import '../../utils/formatting/format.dart'
    show
        formatAvgDamage,
        formatAvgKills,
        formatPercent,
        formatSigned,
        formatSignedInt,
        kNoReading;
import '../../utils/error_messages.dart';
import '../../utils/ranked/ranked_period.dart';
import '../../utils/ranked/slot_compare.dart';
import '../../utils/theme.dart';
import '../../widgets/error_card.dart';
import '../../widgets/nav_entry_card.dart';
import '../../widgets/segmented_capsule.dart';
import '../../widgets/surface_card.dart';
import 'widgets/compare_row.dart';
import 'widgets/ranked_entity_compare.dart';
import 'widgets/ranked_slot_compare_chart.dart';
import 'widgets/split_changes_card.dart';

/// A tappable row that opens the comparison page.
class RankedCompareEntry extends StatelessWidget {
  final String uid;
  final List<RankedSplitBucket> splits;
  final List<RankedMatch> matches;
  const RankedCompareEntry({
    super.key,
    required this.uid,
    required this.splits,
    required this.matches,
  });

  @override
  Widget build(BuildContext context) {
    return NavEntryCard(
      icon: Icons.compare_arrows,
      title: 'Compare',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              RankedCompareScreen(uid: uid, splits: splits, matches: matches),
        ),
      ),
    );
  }
}

/// The comparison page: splits, legends or maps side by side.
class RankedCompareScreen extends StatelessWidget {
  final String uid;
  final List<RankedSplitBucket> splits;
  final List<RankedMatch> matches;
  const RankedCompareScreen({
    super.key,
    required this.uid,
    required this.splits,
    required this.matches,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            RankedCompareTab(uid: uid, splits: splits, matches: matches),
          ],
        ),
      ),
    );
  }
}

/// Split-vs-split comparison. Embedded inline (not in its own scrollable) on
/// the Compare page; the caller supplies the surrounding `ListView`.
///
/// Only real, named splits are selectable — not Lifetime (comparing "every
/// split combined" against one split isn't a split-vs-split comparison) and
/// not Unknown (a grab-bag of unclassified matches spanning an arbitrary
/// timeframe, not a coherent period).
///
/// Net RP is the only cross-split RP figure ever shown. A split's *current*
/// RP is never compared against another split's, because the ladder resets
/// between splits, so a diff of two absolute RP values across that boundary
/// means nothing.
///
/// A selector at the top switches between comparing two splits (the default),
/// and two legends or two maps within [matches], the screen's own period.
class RankedCompareTab extends ConsumerStatefulWidget {
  final String uid;
  final List<RankedSplitBucket> splits;

  /// The ranked games of the period the screen is showing, for the legend and
  /// map comparisons.
  final List<RankedMatch> matches;

  const RankedCompareTab({
    super.key,
    required this.uid,
    required this.splits,
    this.matches = const [],
  });

  @override
  ConsumerState<RankedCompareTab> createState() => _RankedCompareTabState();
}

enum _CompareMode { splits, legends, maps }

class _RankedCompareTabState extends ConsumerState<RankedCompareTab> {
  _CompareMode _mode = _CompareMode.splits;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SegmentedCapsule(
            options: const ['Splits', 'Legends', 'Maps'],
            selected: _mode.index,
            onChanged: (i) => setState(() => _mode = _CompareMode.values[i]),
          ),
        ),
        const SizedBox(height: AppTheme.md),
        switch (_mode) {
          _CompareMode.splits => _buildSplits(),
          _CompareMode.legends => RankedEntityCompare(
            kind: CompareKind.legends,
            matches: widget.matches,
          ),
          _CompareMode.maps => RankedEntityCompare(
            kind: CompareKind.maps,
            matches: widget.matches,
          ),
        },
      ],
    );
  }

  Widget _buildSplits() {
    final real = _comparable;
    if (real.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.lg),
        child: Center(
          child: Text(
            'Need at least two splits with recorded history to compare.',
            textAlign: TextAlign.center,
            style: AppTheme.captionLarge,
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
            child: Text('vs', style: AppTheme.captionLarge),
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
          padding: const EdgeInsets.only(bottom: AppTheme.xs, left: 2),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.lg),
        child: ErrorCard(
          message: friendlyError(error),
          onRetry: () {
            ref.invalidate(
              rankedSplitDetailProvider((uid: uid, splitId: bucketA.id)),
            );
            ref.invalidate(
              rankedSplitDetailProvider((uid: uid, splitId: bucketB.id)),
            );
          },
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
        SplitChangesCard(
          legendsA: a.legends,
          legendsB: b.legends,
          mapsA: a.maps,
          mapsB: b.maps,
        ),
        const SizedBox(height: AppTheme.md),
        RankedSlotCompareChart.hours(
          nameA: bucketA.displayName,
          nameB: bucketB.displayName,
          a: hourSlots(a.timeOfDay),
          b: hourSlots(b.timeOfDay),
        ),
        const SizedBox(height: AppTheme.md),
        RankedSlotCompareChart.days(
          nameA: bucketA.displayName,
          nameB: bucketB.displayName,
          a: weekdaySlots(a.dayOfWeek),
          b: weekdaySlots(b.dayOfWeek),
        ),
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
      child: Text(text, style: AppTheme.cardTitle),
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
          CompareTable(
            nameA: bucketA.displayName,
            nameB: bucketB.displayName,
            rows: [
              CompareRow(
                'Games',
                '${a.summary.games}',
                '${b.summary.games}',
                delta: (b.summary.games - a.summary.games).toDouble(),
                integerDelta: true,
                // Needing more games for a comparable result reads as worse,
                // not better, so this is the one row where "more" colors red.
                invert: true,
              ),
              CompareRow(
                'Games/day',
                gamesPerDayA == null
                    ? kNoReading
                    : gamesPerDayA.toStringAsFixed(1),
                gamesPerDayB == null
                    ? kNoReading
                    : gamesPerDayB.toStringAsFixed(1),
                delta: (gamesPerDayA != null && gamesPerDayB != null)
                    ? gamesPerDayB - gamesPerDayA
                    : null,
                invert: true,
              ),
              CompareRow(
                'Net RP',
                formatSignedInt(a.summary.netRp),
                formatSignedInt(b.summary.netRp),
                delta: (b.summary.netRp - a.summary.netRp).toDouble(),
                integerDelta: true,
              ),
              CompareRow(
                'RP/day',
                rpPerDayA == null ? kNoReading : formatSigned(rpPerDayA),
                rpPerDayB == null ? kNoReading : formatSigned(rpPerDayB),
                delta: (rpPerDayA != null && rpPerDayB != null)
                    ? rpPerDayB - rpPerDayA
                    : null,
              ),
              CompareRow(
                'Avg RP/game',
                formatSigned(a.summary.avgRpPerGame),
                formatSigned(b.summary.avgRpPerGame),
                delta: b.summary.avgRpPerGame - a.summary.avgRpPerGame,
              ),
              CompareRow(
                'Win rate',
                formatPercent(a.summary.winRate),
                formatPercent(b.summary.winRate),
                delta: (b.summary.winRate - a.summary.winRate) * 100,
              ),
              CompareRow(
                'Avg Kills',
                formatAvgKills(a.summary.avgKills),
                formatAvgKills(b.summary.avgKills),
                delta: _diff(a.summary.avgKills, b.summary.avgKills),
              ),
              CompareRow(
                'Avg Dmg',
                formatAvgDamage(a.summary.avgDamage),
                formatAvgDamage(b.summary.avgDamage),
                delta: _diff(a.summary.avgDamage, b.summary.avgDamage),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// [b] minus [a], or null when either side has no reading to compare.
double? _diff(double? a, double? b) => a == null || b == null ? null : b - a;
