import 'package:flutter/material.dart';
import '../../models/player_stats.dart';
import '../../models/rank_info.dart';
import '../../utils/formatting/format.dart' show formatNumber, capitalize;
import '../../utils/formatting/tracker_utils.dart';
import '../../utils/theme.dart';

class PlayerCompareSheet extends StatelessWidget {
  final PlayerStats me;
  final PlayerStats them;
  final String selection; // 'Ranked' or a legend name

  const PlayerCompareSheet({
    super.key,
    required this.me,
    required this.them,
    required this.selection,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    selection,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: AppTheme.muted,
                  ),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.sm),
            const Divider(color: AppTheme.surface2, height: 1),
            const SizedBox(height: AppTheme.sm),

            if (selection == 'Ranked')
              _RankedCompare(me: me, them: them)
            else
              _LegendCompare(me: me, them: them, legendName: selection),
          ],
        ),
      ),
    );
  }
}

// ── Ranked compare content ────────────────────────────────────────────────────

class _RankedCompare extends StatelessWidget {
  final PlayerStats me;
  final PlayerStats them;

  const _RankedCompare({required this.me, required this.them});

  @override
  Widget build(BuildContext context) {
    final myInfo = RankInfo.from(me);
    final theirInfo = RankInfo.from(them);

    final higherRp = me.rankScore > them.rankScore;

    // RP needed is only colored when both players share the same rank tier
    final sameRankTier =
        myInfo.tier != null &&
        theirInfo.tier != null &&
        myInfo.tier == theirInfo.tier;
    final myNeededColor =
        sameRankTier &&
            myInfo.rpToNext != null &&
            theirInfo.rpToNext != null &&
            myInfo.rpToNext != theirInfo.rpToNext
        ? (myInfo.rpToNext! < theirInfo.rpToNext!
              ? AppTheme.green
              : AppTheme.red)
        : AppTheme.textPrimary;
    final theirNeededColor =
        sameRankTier &&
            myInfo.rpToNext != null &&
            theirInfo.rpToNext != null &&
            myInfo.rpToNext != theirInfo.rpToNext
        ? (theirInfo.rpToNext! < myInfo.rpToNext!
              ? AppTheme.green
              : AppTheme.red)
        : AppTheme.textPrimary;

    return Column(
      children: [
        _CompareHeader(theirName: them.name),

        // Rank row
        _CompareRow(
          label: 'Rank',
          myChild: Text(
            myInfo.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: myInfo.color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          theirChild: Text(
            theirInfo.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theirInfo.color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          shaded: false,
        ),

        // RP row
        _CompareRow(
          label: 'RP',
          myChild: Text(
            formatNumber(me.rankScore),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: me.rankScore != them.rankScore
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: higherRp
                  ? AppTheme.green
                  : (me.rankScore != them.rankScore
                        ? AppTheme.red
                        : AppTheme.textPrimary),
            ),
          ),
          theirChild: Text(
            formatNumber(them.rankScore),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.normal,
              color: AppTheme.textPrimary,
            ),
          ),
          shaded: true,
        ),

        // Next rank row
        if (myInfo.nextLabel != null || theirInfo.nextLabel != null)
          _CompareRow(
            label: 'Next rank',
            myChild: Text(
              myInfo.nextLabel ?? '—',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
            theirChild: Text(
              theirInfo.nextLabel ?? '—',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
            shaded: false,
          ),

        // RP needed row
        if (myInfo.rpToNext != null || theirInfo.rpToNext != null)
          _CompareRow(
            label: 'RP needed',
            myChild: Text(
              myInfo.rpToNext != null
                  ? '${formatNumber(myInfo.rpToNext!)} RP'
                  : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: myNeededColor != AppTheme.textPrimary
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: myNeededColor,
              ),
            ),
            theirChild: Text(
              theirInfo.rpToNext != null
                  ? '${formatNumber(theirInfo.rpToNext!)} RP'
                  : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: theirNeededColor != AppTheme.textPrimary
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: theirNeededColor,
              ),
            ),
            shaded: true,
          ),
      ],
    );
  }
}

// ── Legend compare content ────────────────────────────────────────────────────

class _LegendCompare extends StatelessWidget {
  final PlayerStats me;
  final PlayerStats them;
  final String legendName;

  const _LegendCompare({
    required this.me,
    required this.them,
    required this.legendName,
  });

  Map<String, int> _statsFor(PlayerStats player) {
    final matches = player.legendStats.where((l) => l.name == legendName);
    return matches.isEmpty ? {} : trackerValueMap(matches.first.trackers);
  }

  @override
  Widget build(BuildContext context) {
    final myStats = _statsFor(me);
    final theirStats = _statsFor(them);

    final allKeys = {...myStats.keys, ...theirStats.keys}.toList();

    if (allKeys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.md),
        child: Text(
          'No $legendName stats available for either player',
          style: const TextStyle(color: AppTheme.muted, fontSize: 13),
        ),
      );
    }

    return Column(
      children: [
        _CompareHeader(theirName: them.name),
        ...allKeys.asMap().entries.map((entry) {
          final statName = entry.value;
          final myVal = myStats[statName];
          final theirVal = theirStats[statName];
          final color = myVal != null && theirVal != null
              ? (myVal > theirVal
                    ? AppTheme.green
                    : (myVal < theirVal ? AppTheme.red : AppTheme.textPrimary))
              : AppTheme.textPrimary;

          return _CompareRow(
            label: capitalize(statName),
            myChild: Text(
              myVal != null ? formatNumber(myVal) : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    myVal != null && theirVal != null && myVal != theirVal
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: color,
              ),
            ),
            theirChild: Text(
              theirVal != null ? formatNumber(theirVal) : '—',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
                color: AppTheme.textPrimary,
              ),
            ),
            shaded: entry.key.isOdd,
          );
        }),
      ],
    );
  }
}

// ── Shared compare row ────────────────────────────────────────────────────────

class _CompareRow extends StatelessWidget {
  final String label;
  final Widget myChild;
  final Widget theirChild;
  final bool shaded;

  const _CompareRow({
    required this.label,
    required this.myChild,
    required this.theirChild,
    required this.shaded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: shaded ? AppTheme.surface2.withAlpha(60) : null,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ),
          Expanded(child: myChild),
          Expanded(child: theirChild),
        ],
      ),
    );
  }
}

// ── Compare table header ──────────────────────────────────────────────────────

class _CompareHeader extends StatelessWidget {
  final String theirName;

  const _CompareHeader({required this.theirName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.sm),
      child: Row(
        children: [
          const Spacer(flex: 2),
          const Expanded(
            child: Text(
              'You',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              theirName,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
