import 'package:flutter/material.dart';
import '../../../utils/formatting/format.dart' show formatNumber;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

/// Ranked performance split by whether the party was full. "Full squad" is
/// upstream's own `isPartyFull` flag; "Partial squad" covers everything else
/// (duo or solo — upstream doesn't distinguish those further). Takes
/// precomputed summaries so it works off either the in-memory split's matches
/// or the SQL Lifetime scope.
class RankedSquadBreakdownCard extends StatelessWidget {
  final RankedSummary full;
  final RankedSummary partial;
  const RankedSquadBreakdownCard({
    super.key,
    required this.full,
    required this.partial,
  });

  @override
  Widget build(BuildContext context) {
    if (full.games == 0 && partial.games == 0) return const SizedBox.shrink();

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FULL VS PARTIAL SQUAD',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.muted,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppTheme.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SquadColumn(label: 'Full squad', summary: full),
                ),
                const VerticalDivider(
                  color: AppTheme.surface2,
                  width: AppTheme.md,
                ),
                Expanded(
                  child: _SquadColumn(label: 'Partial squad', summary: partial),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SquadColumn extends StatelessWidget {
  final String label;
  final RankedSummary summary;
  const _SquadColumn({required this.label, required this.summary});

  @override
  Widget build(BuildContext context) {
    if (summary.games == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          const Text(
            'No games',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
        ],
      );
    }
    final avgRp = summary.avgRpPerGame;
    final positive = avgRp >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          '${formatNumber(summary.games)} games',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${positive ? '+' : ''}${avgRp.toStringAsFixed(1)} RP/game',
          style: TextStyle(
            color: positive ? AppTheme.green : AppTheme.red,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${(summary.winRate * 100).toStringAsFixed(0)}% win rate',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      ],
    );
  }
}
