import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/formatting/format.dart' show formatNumber;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

/// Recent play sessions (matches grouped by >2h gaps), newest first.
class RankedSessionsCard extends StatelessWidget {
  final List<RankedMatch> matches;
  const RankedSessionsCard({super.key, required this.matches});

  static final _fmt = DateFormat('MMM d, h:mm a');

  @override
  Widget build(BuildContext context) {
    final sessions = sessionize(matches);
    if (sessions.isEmpty) return const SizedBox.shrink();
    final shown = sessions.take(6).toList();

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sessions',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.muted,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppTheme.sm),
          ...shown.asMap().entries.map((e) {
            final last = e.key == shown.length - 1;
            return Column(
              children: [
                _SessionRow(session: e.value, fmt: _fmt),
                if (!last)
                  const Divider(color: AppTheme.surface2, height: AppTheme.md),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final RankedSession session;
  final DateFormat fmt;
  const _SessionRow({required this.session, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final positive = session.netRp >= 0;
    final color = positive ? AppTheme.green : AppTheme.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmt.format(session.start.toLocal()),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${session.games} games · ${session.totalKills} kills',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Text(
              '${positive ? '+' : ''}${formatNumber(session.netRp)} RP',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
