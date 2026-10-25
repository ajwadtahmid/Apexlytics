import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ranked_match.dart';
import '../../models/season_meta.dart';
import '../../providers/ranked_provider.dart';
import '../../providers/settings_provider.dart';
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
import 'widgets/ranked_slot_chart.dart';
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

  /// Whose games the Comparing side shows; null is the profile on screen. The
  /// Current side is always the profile on screen.
  String? _uidA;

  /// The real, named splits [uid] has games in, newest first. The profile on
  /// screen's come from the page; another profile's are read from its history.
  List<RankedSplitBucket> _splitsFor(String uid) =>
      (uid == widget.uid
              ? widget.splits
              : ref.watch(rankedSplitsProvider(uid)).value ?? const [])
          .where((b) => b.id != kLifetimeSplitId && b.id != kUnknownSplitId)
          .toList();

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

  /// The split in [real] with [id], else the one at [index] (clamped): A
  /// defaults to the split before the current one, B to the current one, since
  /// splits sort newest-first.
  RankedSplitBucket? _pick(
    List<RankedSplitBucket> real,
    String? id,
    int index,
  ) {
    if (real.isEmpty) return null;
    return real.firstWhere(
      (b) => b.id == id,
      orElse: () => real[index < real.length ? index : 0],
    );
  }

  Widget _buildSplits() {
    final profiles = [
      for (final p in ref.watch(
        playerSettingsProvider.select((s) => s.profiles),
      ))
        if (p.isSet) p,
    ];
    final multi = profiles.length > 1;
    final uidA = _uidA ?? widget.uid;
    final uidB = widget.uid;
    final sameProfile = uidA == uidB;
    final realA = _splitsFor(uidA);
    final realB = _splitsFor(uidB);
    final bucketA = _pick(realA, _splitAId, 1);
    final bucketB = _pick(realB, _splitBId, 0);

    // Two splits of one profile need two splits; two profiles need one each.
    final canCompare =
        bucketA != null &&
        bucketB != null &&
        (!sameProfile || realA.length >= 2);
    const needMore = Padding(
      padding: EdgeInsets.symmetric(vertical: AppTheme.lg),
      child: Center(
        child: Text(
          'Need at least two splits with recorded history to compare.',
          textAlign: TextAlign.center,
          style: AppTheme.captionLarge,
        ),
      ),
    );
    if (!multi && !canCompare) return needMore;

    String nameOf(String uid) => profiles
        .firstWhere((p) => p.uid == uid, orElse: () => profiles.first)
        .name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SplitPicker(
          splitsA: realA,
          splitsB: realB,
          selectedA: bucketA?.id,
          selectedB: bucketB?.id,
          onChangedA: (id) => setState(() => _splitAId = id),
          onChangedB: (id) => setState(() => _splitBId = id),
          profiles: multi ? {for (final p in profiles) p.uid: p.name} : null,
          profileA: uidA,
          nameB: multi ? nameOf(uidB) : null,
          // Another profile starts on the split you are looking at, so the
          // first thing you see is the two of you over the same split.
          onProfileA: (uid) => setState(() {
            _uidA = uid == widget.uid ? null : uid;
            _splitAId = uid == widget.uid ? null : bucketB?.id;
          }),
        ),
        const SizedBox(height: AppTheme.md),
        if (!canCompare)
          needMore
        else
          _CompareBody(
            uidA: uidA,
            uidB: uidB,
            bucketA: bucketA,
            bucketB: bucketB,
            nameA: sameProfile
                ? bucketA.displayName
                : '${nameOf(uidA)} · ${bucketA.displayName}',
            nameB: sameProfile
                ? bucketB.displayName
                : '${nameOf(uidB)} · ${bucketB.displayName}',
            note: sameProfile
                ? null
                : 'Splits can differ in length, map rotation, and legend '
                      'balance, and each profile\'s games are the ones '
                      'recorded on this device.',
          ),
      ],
    );
  }
}

class _SplitPicker extends StatelessWidget {
  final List<RankedSplitBucket> splitsA;
  final List<RankedSplitBucket> splitsB;
  final String? selectedA;
  final String? selectedB;
  final ValueChanged<String> onChangedA;
  final ValueChanged<String> onChangedB;

  /// Saved profiles by UID, or null with just one, when there is nothing to
  /// choose between and the labels stay plain.
  final Map<String, String>? profiles;
  final String profileA;

  /// The profile on screen, named on the fixed Current side; null with one.
  final String? nameB;
  final ValueChanged<String> onProfileA;

  const _SplitPicker({
    required this.splitsA,
    required this.splitsB,
    required this.selectedA,
    required this.selectedB,
    required this.onChangedA,
    required this.onChangedB,
    required this.profiles,
    required this.profileA,
    required this.nameB,
    required this.onProfileA,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _LabeledDropdown(
            label: 'Comparing',
            splits: splitsA,
            value: selectedA,
            onChanged: onChangedA,
            profiles: profiles,
            profile: profileA,
            onProfile: onProfileA,
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
            label: nameB == null ? 'Current' : 'Current · $nameB',
            splits: splitsB,
            value: selectedB,
            onChanged: onChangedB,
          ),
        ),
      ],
    );
  }
}

const _kLabelStyle = TextStyle(
  color: AppTheme.muted,
  fontSize: 10,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.5,
);

class _LabeledDropdown extends StatelessWidget {
  final String label;
  final List<RankedSplitBucket> splits;
  final String? value;
  final ValueChanged<String> onChanged;

  /// Saved profiles by UID, to choose this side's from; null for a plain label.
  final Map<String, String>? profiles;
  final String profile;
  final ValueChanged<String>? onProfile;

  const _LabeledDropdown({
    required this.label,
    required this.splits,
    required this.value,
    required this.onChanged,
    this.profiles,
    this.profile = '',
    this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final names = profiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.xs, left: 2),
          child: names == null
              ? Text(label.toUpperCase(), style: _kLabelStyle)
              : PopupMenuButton<String>(
                  tooltip: 'Choose profile',
                  color: AppTheme.surface,
                  onSelected: onProfile,
                  itemBuilder: (_) => [
                    for (final e in names.entries)
                      PopupMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '${label.toUpperCase()} · '
                          '${(names[profile] ?? '').toUpperCase()}',
                          overflow: TextOverflow.ellipsis,
                          style: _kLabelStyle.copyWith(color: AppTheme.accent),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: AppTheme.accent,
                      ),
                    ],
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
  final String? value;
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
          hint: const Text(
            'No recorded games',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
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
  /// Whose games each side is. The same for a split against a split.
  final String uidA;
  final String uidB;
  final RankedSplitBucket bucketA;
  final RankedSplitBucket bucketB;
  final String nameA;
  final String nameB;

  /// Replaces the line about splits differing, where that is not the point.
  final String? note;

  const _CompareBody({
    required this.uidA,
    required this.uidB,
    required this.bucketA,
    required this.bucketB,
    required this.nameA,
    required this.nameB,
    this.note,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aAsync = ref.watch(
      rankedSplitDetailProvider((uid: uidA, splitId: bucketA.id)),
    );
    final bAsync = ref.watch(
      rankedSplitDetailProvider((uid: uidB, splitId: bucketB.id)),
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
              rankedSplitDetailProvider((uid: uidA, splitId: bucketA.id)),
            );
            ref.invalidate(
              rankedSplitDetailProvider((uid: uidB, splitId: bucketB.id)),
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
        _Disclaimer(note),
        const SizedBox(height: AppTheme.md),
        _SummarySection(
          bucketA: bucketA,
          bucketB: bucketB,
          nameA: nameA,
          nameB: nameB,
          a: a,
          b: b,
        ),
        const SizedBox(height: AppTheme.md),
        // What changed from one split to the next means nothing between two
        // people.
        if (uidA == uidB) ...[
          SplitChangesCard(
            legendsA: a.legends,
            legendsB: b.legends,
            mapsA: a.maps,
            mapsB: b.maps,
          ),
          const SizedBox(height: AppTheme.md),
        ],
        RankedSlotChart.hours(
          nameA: nameA,
          nameB: nameB,
          a: hourSlots(a.timeOfDay),
          b: hourSlots(b.timeOfDay),
        ),
        const SizedBox(height: AppTheme.md),
        RankedSlotChart.days(
          nameA: nameA,
          nameB: nameB,
          a: weekdaySlots(a.dayOfWeek),
          b: weekdaySlots(b.dayOfWeek),
        ),
      ],
    );
  }
}

class _Disclaimer extends StatelessWidget {
  final String? note;
  const _Disclaimer(this.note);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.sm),
      child: Text(
        note ??
            'Splits can differ in length, map rotation, and legend balance — '
                'treat differences as a starting point, not a verdict.',
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 11,
          height: 1.4,
        ),
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
  final String nameA;
  final String nameB;
  final RankedSplitDetail a;
  final RankedSplitDetail b;

  const _SummarySection({
    required this.bucketA,
    required this.bucketB,
    required this.nameA,
    required this.nameB,
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
            nameA: nameA,
            nameB: nameB,
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
                'Avg RP',
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
                'Avg Damage',
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
