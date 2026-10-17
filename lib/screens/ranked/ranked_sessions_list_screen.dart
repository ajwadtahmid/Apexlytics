import 'package:flutter/material.dart';
import '../../utils/formatting/format.dart' show formatSignedInt, plural;
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/ranked/session_groups.dart';
import '../../utils/ranked/session_overview.dart';
import '../../utils/theme.dart';
import 'ranked_session_detail_screen.dart';
import 'ranked_sessions_screen.dart';
import 'widgets/sessions_overview.dart';
import '../../widgets/nav_entry_card.dart';

/// Entry point for the Sessions screen. [sessions] is the
/// same list already memoized by `rankedSplitViewProvider`, rather than this
/// widget sessionizing its own `matches` on every rebuild of the
/// always-visible Overview tab. Expected empty at Lifetime
/// scope (sessions are a split-relative concept — see
/// [RankedSessionsListScreen]). Hides itself when there's nothing to show.
class RankedSessionsEntry extends StatelessWidget {
  final List<RankedSession> sessions;
  final Future<void> Function() onRefresh;

  const RankedSessionsEntry({
    super.key,
    required this.sessions,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();

    return NavEntryCard(
      icon: Icons.timeline,
      title: 'Sessions',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RankedSessionsListScreen(
            sessions: sessions,
            onRefresh: onRefresh,
          ),
        ),
      ),
    );
  }
}

/// Full-screen sessions page: what they add up to and an RP bar per session
/// on top, then every session as a card under a heading for when it was played
/// (Today, Yesterday, This week...) with that stretch's total. The list builds
/// its cards as they scroll into view, so there is nothing to tap to load more.
/// Pass an empty [sessions] list at Lifetime scope, where sessions were never
/// offered (too heavy at that scale, and RP resets each split anyway).
class RankedSessionsListScreen extends StatelessWidget {
  final List<RankedSession> sessions;
  final Future<void> Function() onRefresh;

  /// Stands in for the current time when sorting sessions under headings.
  @visibleForTesting
  final DateTime? now;

  const RankedSessionsListScreen({
    super.key,
    required this.sessions,
    required this.onRefresh,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final overview = sessionOverview(sessions);
    // With one session, "best" and "worst" would both be it.
    SessionBadge? badgeOf(RankedSession s) {
      if (overview == null || sessions.length < 2) return null;
      if (identical(s, overview.best)) return SessionBadge.best;
      if (identical(s, overview.worst)) return SessionBadge.worst;
      return null;
    }

    void open(RankedSession s) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RankedSessionDetailScreen(session: s, onRefresh: onRefresh),
      ),
    );

    // Headings and sessions in one run, so the list builds either lazily.
    final rows = <Object>[
      for (final g in groupSessions(sessions, now: now)) ...[g, ...g.sessions],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            if (sessions.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.all(AppTheme.md),
                sliver: SliverToBoxAdapter(
                  child: SessionsOverview(sessions: sessions, onOpen: open),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.md,
                  0,
                  AppTheme.md,
                  AppTheme.md,
                ),
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is SessionGroup) {
                      return _GroupHeader(group: row, first: i == 0);
                    }
                    final s = row as RankedSession;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.sm),
                      child: SessionRecapTile(
                        session: s,
                        badge: badgeOf(s),
                        onTap: () => open(s),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A heading over a run of sessions: when they were played, and how many and
/// what they netted.
class _GroupHeader extends StatelessWidget {
  final SessionGroup group;
  final bool first;
  const _GroupHeader({required this.group, required this.first});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 0 : AppTheme.md,
        bottom: AppTheme.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: AppTheme.cardTitle,
            ),
          ),
          const SizedBox(width: AppTheme.sm),
          Text(
            '${plural(group.sessions.length, 'session')} · ',
            style: AppTheme.captionSmall,
          ),
          Text(
            '${formatSignedInt(group.netRp)} RP',
            style: TextStyle(
              color: AppTheme.signColor(group.netRp >= 0),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
