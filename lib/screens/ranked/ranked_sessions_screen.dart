import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/formatting/format.dart' show formatDuration, formatNumber;
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';
import 'ranked_entity_history_screen.dart';
import 'widgets/ranked_match_list.dart' show MatchGrouping;

final _sessionDateFmt = DateFormat('MMM d · h:mm a');
final _sessionDayFmt = DateFormat('MMM d');

/// Opens a single session's games as a filtered history (newest first), grouped
/// by legend when the user toggles sort — same drill-down used for legends/maps.
void openSessionHistory(
  BuildContext context,
  RankedSession session,
  Future<void> Function() onRefresh,
) {
  final net = session.netRp;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => RankedEntityHistoryScreen(
      title: _sessionDayFmt.format(session.start.toLocal()),
      subtitle:
          '${session.games} games · ${net >= 0 ? '+' : ''}${formatNumber(net)} RP',
      matches: session.matches,
      onRefresh: onRefresh,
      groupLabel: 'legend',
      grouping: MatchGrouping(keyOf: (m) => m.legend, nameOf: (m) => m.legend),
    ),
  ));
}

/// Full list of recent sessions (newest first). Tapping a row drills into that
/// session's games.
class RankedSessionsScreen extends StatelessWidget {
  final List<RankedSession> sessions;
  final Future<void> Function() onRefresh;

  const RankedSessionsScreen({
    super.key,
    required this.sessions,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recent sessions')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(AppTheme.md),
          itemCount: sessions.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppTheme.sm),
          itemBuilder: (context, i) => SessionRecapTile(
            session: sessions[i],
            onTap: () => openSessionHistory(context, sessions[i], onRefresh),
          ),
        ),
      ),
    );
  }
}

/// A tappable session summary as its own card. Used by the recent-sessions
/// screen; the Overview card embeds [SessionRecapBody] directly instead.
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
/// time · top legend). Shared by [SessionRecapTile] and the Overview card.
class SessionRecapBody extends StatelessWidget {
  final RankedSession session;
  const SessionRecapBody({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final positive = session.netRp >= 0;
    final rpColor = positive ? AppTheme.green : AppTheme.red;
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
            _stat('${session.totalKills}', 'kills'),
            _stat(formatDuration(session.duration.inSeconds), 'played'),
            if (best != null) _stat(best, 'top legend', flex: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: rpColor.withAlpha(30),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Text(
                '${positive ? '+' : ''}${formatNumber(session.netRp)} RP',
                style: TextStyle(
                  color: rpColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
        ),
      );
}
