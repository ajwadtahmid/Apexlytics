import 'package:flutter/material.dart';
import '../../constants/api_constants.dart';
import '../../constants/legend_constants.dart' show legendDisplayName;
import '../../models/player_stats.dart';
import '../../models/rank_info.dart';
import '../../utils/formatting/format.dart' show formatNumber, timeAgo;
import '../../utils/formatting/rank_utils.dart' show rankAssetPath;
import '../../utils/theme.dart';
import '../../utils/tracking/player_compare.dart';
import '../../widgets/legend_icon.dart';
import '../../widgets/rank_badge.dart';
import '../../widgets/widgets.dart';
import '../ranked/widgets/compare_row.dart';

/// You against another player: who they are, then the ranked figures or one
/// legend, with the gap on every row and the better side marked.
class PlayerCompareScreen extends StatefulWidget {
  final PlayerStats me;
  final PlayerStats them;

  const PlayerCompareScreen({super.key, required this.me, required this.them});

  @override
  State<PlayerCompareScreen> createState() => _PlayerCompareScreenState();
}

/// The reader's side is the accent, the other player's the muted one.
const _kYou = AppTheme.accent;
const _kThem = AppTheme.muted;

class _PlayerCompareScreenState extends State<PlayerCompareScreen> {
  late final List<LegendOption> _options = legendOptions(
    widget.me,
    widget.them,
  );
  var _showLegend = false;
  late String? _legend = _options.isEmpty ? null : _options.first.name;

  CompareRow _row(CompareLine l) => CompareRow(
    l.label,
    l.valueA,
    l.valueB,
    delta: l.delta,
    integerDelta: l.integerDelta,
    decimals: l.decimals,
    invert: l.invert,
    deltaFromFirst: true,
    colorA: _kYou,
    colorB: _kThem,
  );

  CompareTable _table(List<CompareLine> lines, {bool showKey = true}) =>
      CompareTable(
        nameA: 'You',
        nameB: widget.them.name,
        firstIsYou: true,
        colorA: _kYou,
        colorB: _kThem,
        showKey: showKey,
        rows: [for (final l in lines) _row(l)],
      );

  Future<void> _pickLegend() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LegendSheet(options: _options, selected: _legend),
    );
    if (picked != null && mounted) setState(() => _legend = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            _IdentityStrip(me: widget.me, them: widget.them),
            const SizedBox(height: AppTheme.md),
            Center(
              child: SegmentedCapsule(
                options: const ['Ranked', 'Legend'],
                selected: _showLegend ? 1 : 0,
                onChanged: (i) => setState(() => _showLegend = i == 1),
              ),
            ),
            const SizedBox(height: AppTheme.md),
            if (_showLegend) ..._legendSection() else ..._rankedSection(),
          ],
        ),
      ),
    );
  }

  List<Widget> _rankedSection() => [
    _table(rankedCompareLines(widget.me, widget.them)),
    const SizedBox(height: AppTheme.sm),
    const Text('The Rank change counts divisions.', style: AppTheme.caption),
  ];

  List<Widget> _legendSection() {
    final legend = _legend;
    if (legend == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppTheme.lg),
          child: Text(
            'Neither of you has legend stats to compare yet.',
            textAlign: TextAlign.center,
            style: AppTheme.captionLarge,
          ),
        ),
      ];
    }
    final option = _options.firstWhere((o) => o.name == legend);
    final data = legendCompare(widget.me, widget.them, legend);
    final stale = [data.updatedA, data.updatedB].whereType<DateTime>().any(
      (t) => DateTime.now().difference(t) > const Duration(days: 1),
    );
    return [
      _LegendSelector(option: option, onTap: _pickLegend),
      const SizedBox(height: AppTheme.md),
      if (data.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppTheme.lg),
          child: Text(
            'No stats for either player on this legend.',
            textAlign: TextAlign.center,
            style: AppTheme.captionLarge,
          ),
        )
      else ...[
        if (data.trackers.isNotEmpty) ...[
          const SectionLabel(label: 'Trackers', icon: Icons.bar_chart),
          _table(data.trackers),
          const SizedBox(height: AppTheme.md),
        ],
        const SectionLabel(label: 'Calculated', icon: Icons.insights_outlined),
        if (data.calculated.isNotEmpty)
          _table(data.calculated, showKey: data.trackers.isEmpty)
        else
          const Text(
            'Per-game figures need the Games Played, Kills and Damage '
            'trackers equipped.',
            style: AppTheme.caption,
          ),
        if (data.lowSample) ...[
          const SizedBox(height: AppTheme.sm),
          Text(
            'Few games on this legend (you: ${data.gamesA ?? '—'}, '
            '${widget.them.name}: ${data.gamesB ?? '—'}). Per-game figures '
            'can swing a lot over a handful of games.',
            style: AppTheme.caption,
          ),
        ],
        if (stale) ...[
          const SizedBox(height: AppTheme.md),
          Text(
            'Updated: you ${_ago(data.updatedA)}, '
            '${widget.them.name} ${_ago(data.updatedB)}.',
            style: AppTheme.captionSmall,
          ),
        ],
      ],
    ];
  }

  String _ago(DateTime? t) => t == null ? 'unknown' : timeAgo(t);
}

/// Who is being compared: a card each, you on the left.
class _IdentityStrip extends StatelessWidget {
  final PlayerStats me;
  final PlayerStats them;

  const _IdentityStrip({required this.me, required this.them});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PlayerCard(stats: me, label: 'You', color: _kYou),
          ),
          const SizedBox(width: AppTheme.sm),
          Expanded(
            child: _PlayerCard(stats: them, label: 'Them', color: _kThem),
          ),
        ],
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final PlayerStats stats;
  final String label;
  final Color color;

  const _PlayerCard({
    required this.stats,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final info = RankInfo.from(stats);
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.sm),
      border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppTheme.xs),
          RankBadge(assetPath: rankAssetPath(stats), size: 48),
          const SizedBox(height: AppTheme.xs),
          Text(
            stats.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            info.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: info.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${formatNumber(stats.rankScore)} RP',
            style: AppTheme.captionLarge,
          ),
          Text(
            'Level ${formatNumber(stats.level)} · '
            '${ApiConstants.labelFor(stats.platform)}',
            textAlign: TextAlign.center,
            style: AppTheme.captionSmall,
          ),
        ],
      ),
    );
  }
}

String _games(int? n) => n == null ? '—' : formatNumber(n);

/// The legend being compared, and the way to pick another.
class _LegendSelector extends StatelessWidget {
  final LegendOption option;
  final VoidCallback onTap;

  const _LegendSelector({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          'Legend: ${legendDisplayName(option.name)}. '
          'Tap to choose another.',
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.md,
          vertical: AppTheme.sm,
        ),
        child: Row(
          children: [
            LegendIcon(legendName: option.name, size: 36),
            const SizedBox(width: AppTheme.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    legendDisplayName(option.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  // Few players equip the Games Played tracker, so say nothing
                  // when neither of you has it.
                  if (option.gamesA != null || option.gamesB != null)
                    Text(
                      'Games: you ${_games(option.gamesA)} · '
                      'them ${_games(option.gamesB)}',
                      style: AppTheme.caption,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.sm),
            const Text(
              'Change',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(Icons.expand_more, color: AppTheme.accent),
          ],
        ),
      ),
    );
  }
}

/// Every legend either of you has stats for, as a grid: the ones you both play
/// first. No sideways scrolling, and each tile says how much each of you has.
class _LegendSheet extends StatelessWidget {
  final List<LegendOption> options;
  final String? selected;

  const _LegendSheet({required this.options, required this.selected});

  @override
  Widget build(BuildContext context) {
    final shared = [
      for (final o in options)
        if (o.shared) o,
    ];
    final single = [
      for (final o in options)
        if (!o.shared) o,
    ];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppTheme.sm),
          const SheetHandle(),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.md,
              AppTheme.md,
              AppTheme.md,
              AppTheme.xs,
            ),
            child: Text(
              'Choose a legend',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (shared.isNotEmpty)
                    _LegendGroup(
                      title: 'You both play',
                      options: shared,
                      selected: selected,
                    ),
                  if (shared.isNotEmpty && single.isNotEmpty)
                    const SizedBox(height: AppTheme.md),
                  if (single.isNotEmpty)
                    _LegendGroup(
                      title: 'Only one of you',
                      options: single,
                      selected: selected,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendGroup extends StatelessWidget {
  final String title;
  final List<LegendOption> options;
  final String? selected;

  const _LegendGroup({
    required this.title,
    required this.options,
    required this.selected,
  });

  static const _columns = 4;
  static const _gap = AppTheme.sm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppTheme.sm),
        LayoutBuilder(
          builder: (context, box) {
            final width = (box.maxWidth - _gap * (_columns - 1)) / _columns;
            return Wrap(
              spacing: _gap,
              runSpacing: _gap,
              children: [
                for (final o in options)
                  SizedBox(
                    width: width,
                    child: _LegendTile(option: o, selected: o.name == selected),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LegendTile extends StatelessWidget {
  final LegendOption option;
  final bool selected;

  const _LegendTile({required this.option, required this.selected});

  @override
  Widget build(BuildContext context) {
    final name = legendDisplayName(option.name);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: GestureDetector(
        onTap: () => Navigator.pop(context, option.name),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.2)
                : AppTheme.surface2,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: selected ? AppTheme.accent : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LegendIcon(legendName: option.name, size: 32),
              const SizedBox(height: 4),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
