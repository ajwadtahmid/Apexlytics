import 'package:flutter/material.dart';
import '../../../constants/map_constants.dart' show isUnknownMapKey;
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart'
    show
        formatAvgDamage,
        formatAvgKills,
        formatPercent,
        formatSigned,
        formatSignedInt,
        plural;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';
import 'compare_row.dart';

/// What a [RankedEntityCompare] sets side by side.
enum CompareKind { legends, maps }

/// One legend's or map's figures for the compared scope.
typedef _Stats = ({
  String name,
  int games,
  int totalRp,
  double avgRp,
  double winRate,
  double? avgKills,
  double? avgDamage,
});

List<_Stats> _statsFor(CompareKind kind, List<RankedMatch> matches) {
  final ranked = rankedOnly(matches);
  final list = switch (kind) {
    CompareKind.legends => <_Stats>[
      for (final l in legendBreakdowns(ranked))
        (
          name: l.legend,
          games: l.games,
          totalRp: l.totalRp,
          avgRp: l.avgRpPerGame,
          winRate: l.winRate,
          avgKills: l.avgKills,
          avgDamage: l.avgDamage,
        ),
    ],
    CompareKind.maps => <_Stats>[
      for (final m in mapBreakdowns(ranked))
        if (!isUnknownMapKey(m.mapKey))
          (
            name: m.displayName,
            games: m.games,
            totalRp: m.totalRp,
            avgRp: m.avgRpPerGame,
            winRate: m.wins + m.losses == 0 ? 0 : m.wins / (m.wins + m.losses),
            avgKills: m.avgKills,
            avgDamage: m.avgDamage,
          ),
    ],
  };
  // Most played first, so the defaults are the two the player knows best.
  return list..sort((a, b) {
    final g = b.games.compareTo(a.games);
    return g != 0 ? g : a.name.compareTo(b.name);
  });
}

/// Two legends, or two maps, from [matches] in one table: games, net RP, RP
/// per game, win rate, kills and damage. The first and second default to the
/// two most played.
class RankedEntityCompare extends StatefulWidget {
  final CompareKind kind;
  final List<RankedMatch> matches;
  const RankedEntityCompare({
    super.key,
    required this.kind,
    required this.matches,
  });

  @override
  State<RankedEntityCompare> createState() => _RankedEntityCompareState();
}

class _RankedEntityCompareState extends State<RankedEntityCompare> {
  String? _a;
  String? _b;

  @override
  Widget build(BuildContext context) {
    final all = _statsFor(widget.kind, widget.matches);
    final noun = widget.kind == CompareKind.legends ? 'legends' : 'maps';
    if (all.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.lg),
        child: Center(
          child: Text(
            'Play at least two $noun in this period to compare them.',
            textAlign: TextAlign.center,
            style: AppTheme.captionLarge,
          ),
        ),
      );
    }
    _Stats pick(String? name, int fallback) =>
        all.firstWhere((s) => s.name == name, orElse: () => all[fallback]);
    final a = pick(_a, 0);
    // The second never defaults to the same one as the first.
    final b = pick(_b, a.name == all[1].name ? 0 : 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _Dropdown(
                options: all,
                value: a.name,
                onChanged: (v) => setState(() => _a = v),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppTheme.sm),
              child: Text('vs', style: AppTheme.captionLarge),
            ),
            Expanded(
              child: _Dropdown(
                options: all,
                value: b.name,
                onChanged: (v) => setState(() => _b = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.md),
        SurfaceCard(
          padding: const EdgeInsets.all(AppTheme.md),
          child: Column(
            children: [
              CompareRow(
                'Games',
                '${a.games}',
                '${b.games}',
                // How often each was picked isn't good or bad.
              ),
              CompareRow(
                'Net RP',
                formatSignedInt(a.totalRp),
                formatSignedInt(b.totalRp),
                delta: (b.totalRp - a.totalRp).toDouble(),
                integerDelta: true,
              ),
              CompareRow(
                'RP/game',
                formatSigned(a.avgRp),
                formatSigned(b.avgRp),
                delta: b.avgRp - a.avgRp,
              ),
              CompareRow(
                'Win rate',
                formatPercent(a.winRate),
                formatPercent(b.winRate),
                delta: (b.winRate - a.winRate) * 100,
              ),
              CompareRow(
                'Avg Kills',
                formatAvgKills(a.avgKills),
                formatAvgKills(b.avgKills),
                delta: _diff(a.avgKills, b.avgKills),
              ),
              CompareRow(
                'Avg Dmg',
                formatAvgDamage(a.avgDamage),
                formatAvgDamage(b.avgDamage),
                delta: _diff(a.avgDamage, b.avgDamage),
              ),
            ],
          ),
        ),
        if (a.games < kMinGamesForInsight || b.games < kMinGamesForInsight)
          const Padding(
            padding: EdgeInsets.only(top: AppTheme.sm),
            child: Text(
              'Under $kMinGamesForInsight games is too few to read much into.',
              style: AppTheme.captionSmall,
            ),
          ),
      ],
    );
  }
}

/// [b] minus [a], or null when either side has no reading to compare.
double? _diff(double? a, double? b) => a == null || b == null ? null : b - a;

class _Dropdown extends StatelessWidget {
  final List<_Stats> options;
  final String value;
  final ValueChanged<String> onChanged;
  const _Dropdown({
    required this.options,
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
            for (final s in options)
              DropdownMenuItem(
                value: s.name,
                child: Text(
                  '${s.name} · ${plural(s.games, 'game')}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
