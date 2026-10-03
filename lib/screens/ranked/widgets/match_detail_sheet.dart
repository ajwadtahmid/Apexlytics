import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../constants/map_constants.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show formatDuration, formatNumber;
import '../../../utils/ranked/legend_baseline.dart';
import '../../../utils/theme.dart';
import '../../../widgets/legend_asset_image.dart';
import '../../../widgets/stat_display.dart';
import 'match_edit_sheet.dart';
import 'match_tags.dart';

/// Opens the detail sheet for `matches[index]`. [matches] is the list in the
/// order the user sees it (already filtered/grouped), so the prev/next arrows
/// walk the same sequence. [baselinePool], when given, is what the legend
/// average comes from; null hides the comparison.
///
/// Resolves to the corrected match when the user saves an edit, else null.
Future<RankedMatch?> showMatchDetailSheet(
  BuildContext context, {
  required List<RankedMatch> matches,
  required int index,
  Iterable<RankedMatch>? baselinePool,
}) {
  return showModalBottomSheet<RankedMatch>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (_) => _MatchDetailSheet(
      matches: matches,
      initialIndex: index,
      baselinePool: baselinePool,
    ),
  );
}

class _MatchDetailSheet extends StatefulWidget {
  final List<RankedMatch> matches;
  final int initialIndex;
  final Iterable<RankedMatch>? baselinePool;
  const _MatchDetailSheet({
    required this.matches,
    required this.initialIndex,
    required this.baselinePool,
  });

  @override
  State<_MatchDetailSheet> createState() => _MatchDetailSheetState();
}

class _MatchDetailSheetState extends State<_MatchDetailSheet> {
  static final _fmt = DateFormat('MMM d, yyyy h:mm a');
  static const _swipeVelocity = 300.0;

  late int _index = widget.initialIndex;

  RankedMatch get _match => widget.matches[_index];
  bool get _hasPrev => _index > 0;
  bool get _hasNext => _index < widget.matches.length - 1;

  void _step(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.matches.length) return;
    setState(() => _index = next);
  }

  void _onSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v > _swipeVelocity) _step(-1); // swipe right → previous
    if (v < -_swipeVelocity) _step(1); // swipe left → next
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    final ranked = match.isRanked;
    final up = match.rpChange >= 0;
    final rpColor = up ? AppTheme.green : AppTheme.red;
    final notes = matchTagNotes(match);
    final pool = widget.baselinePool;
    final baseline = pool == null ? null : legendBaselineFor(match, pool);

    return SafeArea(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _onSwipe,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(match: match, onEdited: _onEdit),
              const SizedBox(height: AppTheme.md),
              if (ranked) ...[
                _RpBlock(match: match, up: up, color: rpColor),
                const SizedBox(height: AppTheme.md),
              ],
              _StatsBlock(match: match, baseline: baseline),
              for (final n in notes) _NoteRow(note: n),
              const SizedBox(height: AppTheme.md),
              const Divider(color: AppTheme.surface2, height: 1),
              const SizedBox(height: AppTheme.md),
              _Trackers(match: match),
              if (widget.matches.length > 1) ...[
                const SizedBox(height: AppTheme.sm),
                _NavRow(
                  position: _index + 1,
                  total: widget.matches.length,
                  onPrev: _hasPrev ? () => _step(-1) : null,
                  onNext: _hasNext ? () => _step(1) : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onEdit() async {
    // Close this sheet too on a real save, passing the updated match back up
    // so the caller (row/list) can show it immediately instead of the stale
    // copy this sheet was opened with.
    final updated = await showMatchEditSheet(context, _match);
    if (updated != null && mounted) Navigator.pop(context, updated);
  }

  static String formatTime(DateTime t) => _fmt.format(t.toLocal());
}

class _Header extends StatelessWidget {
  final RankedMatch match;
  final Future<void> Function() onEdited;
  const _Header({required this.match, required this.onEdited});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: SizedBox(
            width: 64,
            height: 64,
            child: LegendAssetImage(
              imageKey: legendImageKey(match.legend),
              displayName: match.legend,
              fallbackFontSize: 24,
            ),
          ),
        ),
        const SizedBox(width: AppTheme.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                match.legend,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              // The map leads the line, sized to sit beside the mode tag.
              Wrap(
                spacing: AppTheme.sm,
                runSpacing: AppTheme.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    battleRoyaleMapName(match.mapKey),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  MatchModeChip(ranked: match.isRanked),
                  if (match.excluded) const ExcludedTag(),
                  if (match.isEdited) const EditedChip(),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${match.isPartyFull ? 'Full squad' : 'Partial squad'} · '
                '${_MatchDetailSheetState.formatTime(match.endTime)}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          color: AppTheme.muted,
          tooltip: 'Correct this match',
          visualDensity: VisualDensity.compact,
          onPressed: onEdited,
        ),
      ],
    );
  }
}

/// Rank tier, running RP and this game's RP swing.
class _RpBlock extends StatelessWidget {
  final RankedMatch match;
  final bool up;
  final Color color;
  const _RpBlock({required this.match, required this.up, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (match.rankImg.isNotEmpty) ...[
          CachedNetworkImage(
            imageUrl: match.rankImg,
            width: 34,
            height: 34,
            fit: BoxFit.contain,
            memCacheWidth: (34 * MediaQuery.devicePixelRatioOf(context)).ceil(),
            errorWidget: (_, _, _) => const SizedBox(width: 34),
          ),
          const SizedBox(width: AppTheme.sm),
        ],
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ranked Points',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
            Text(
              formatNumber(match.cumulativeRp),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const Spacer(),
        Text(
          '${up ? '+' : ''}${match.rpChange} RP',
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Kills, damage and length as chips, with kills/damage compared to the
/// legend's average when [baseline] has one.
class _StatsBlock extends StatelessWidget {
  final RankedMatch match;
  final LegendBaseline? baseline;
  const _StatsBlock({required this.match, required this.baseline});

  /// "+3.8 vs avg" tinted green/red, or null when there's nothing to compare.
  (String, Color)? _delta(num? value, double? avg, {required int decimals}) {
    if (value == null || avg == null) return null;
    final diff = value - avg;
    final rounded = double.parse(diff.toStringAsFixed(decimals));
    final text = rounded == 0
        ? 'on avg'
        : '${rounded > 0 ? '+' : ''}${decimals == 0 ? formatNumber(rounded.round()) : rounded.toStringAsFixed(decimals)} vs avg';
    final color = rounded == 0
        ? AppTheme.muted
        : (rounded > 0 ? AppTheme.green : AppTheme.red);
    return (text, color);
  }

  @override
  Widget build(BuildContext context) {
    final kills = match.kills;
    final damage = match.damage;
    final killDelta = _delta(kills, baseline?.avgKills, decimals: 1);
    final dmgDelta = _delta(damage, baseline?.avgDamage, decimals: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatGrid(
          rows: [
            [
              StatDisplay(
                centered: true,
                label: 'Kills',
                // An em dash marks a stat upstream never reported, which is
                // not the same as a scoreless game.
                value: kills?.toString() ?? '—',
                footnote: killDelta?.$1,
                footnoteColor: killDelta?.$2,
              ),
              StatDisplay(
                centered: true,
                label: 'Damage',
                value: damage == null ? '—' : formatNumber(damage),
                footnote: dmgDelta?.$1,
                footnoteColor: dmgDelta?.$2,
              ),
              StatDisplay(
                centered: true,
                label: 'Length',
                value: formatDuration(match.lengthSecs),
              ),
            ],
          ],
        ),
        if (killDelta != null || dmgDelta != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Compared with your ${match.legend} average '
              '(${match.isRanked ? 'ranked' : 'casual'}, outliers and '
              'excluded games left out)',
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  final MatchTagNote note;
  const _NoteRow({required this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline, size: 13, color: AppTheme.muted),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              note.text,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Trackers extends StatelessWidget {
  final RankedMatch match;
  const _Trackers({required this.match});

  @override
  Widget build(BuildContext context) {
    if (match.trackers.isEmpty) {
      return const Text(
        'No tracker data for this match',
        style: TextStyle(color: AppTheme.muted, fontSize: 13),
      );
    }
    return Column(
      children: [
        for (final t in match.trackers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    t.name,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                ),
                const SizedBox(width: AppTheme.sm),
                Text(
                  formatNumber(t.value.toInt()),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Faint prev/next arrows with the match's position — present but quiet, so
/// they don't compete with the match itself. Swiping the sheet does the same.
class _NavRow extends StatelessWidget {
  final int position;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _NavRow({
    required this.position,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  Widget _arrow(IconData icon, String tooltip, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0 : 0.45,
      child: IconButton(
        icon: Icon(icon, size: 22),
        color: AppTheme.muted,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _arrow(Icons.chevron_left, 'Previous match', onPrev),
        Text(
          '$position of $total',
          style: TextStyle(color: AppTheme.muted.withAlpha(140), fontSize: 11),
        ),
        _arrow(Icons.chevron_right, 'Next match', onNext),
      ],
    );
  }
}
