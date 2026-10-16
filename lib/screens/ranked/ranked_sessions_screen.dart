import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/formatting/format.dart' show formatDuration, formatShortDate, formatSignedInt, formatTotalOrNone, plural;
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/rp_pill.dart';
import '../../widgets/surface_card.dart';
import 'ranked_entity_history_screen.dart';
import 'widgets/match_history_items.dart' show MatchGrouping;

final _sessionDateFmt = DateFormat('MMM d · h:mm a');

/// Opens a single session's games as a filtered history (newest first), grouped
/// by legend when the user toggles sort — same drill-down used for legends/maps.
void openSessionHistory(
  BuildContext context,
  RankedSession session,
  Future<void> Function() onRefresh,
) {
  final net = session.netRp;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RankedEntityHistoryScreen(
        title: formatShortDate(session.start),
        subtitle:
            '${plural(session.games, 'game')} · ${formatSignedInt(net)} RP',
        matches: session.matches,
        onRefresh: onRefresh,
        groupLabel: 'legend',
        grouping: MatchGrouping.byLegend,
      ),
    ),
  );
}

/// A tappable session summary as its own card. Used by the Sessions
/// screen's session list.
class SessionRecapTile extends StatelessWidget {
  final RankedSession session;
  final VoidCallback onTap;

  const SessionRecapTile({
    super.key,
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.md),
      child: SessionRecapBody(session: session),
    );
  }
}

/// Card-less session summary: date, net RP, and a stat strip (games · kills ·
/// time · top legend). Used by [SessionRecapTile].
class SessionRecapBody extends StatelessWidget {
  final RankedSession session;
  const SessionRecapBody({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final best = session.bestLegend;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _sessionDateFmt.format(session.start.toLocal()),
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTheme.sm),
        Row(
          children: [
            _stat('${session.games}', 'games'),
            _stat(
              formatTotalOrNone(session.totalKills, session.killsGames),
              'kills',
            ),
            _stat(formatDuration(session.duration.inSeconds), 'played'),
            if (best != null) _stat(best, 'top legend', flex: 2),
            RpPill(totalRp: session.netRp),
          ],
        ),
      ],
    );
  }

  Widget _stat(String value, String label, {int flex = 1}) => Expanded(
    flex: flex,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTheme.captionSmall,
        ),
      ],
    ),
  );
}
