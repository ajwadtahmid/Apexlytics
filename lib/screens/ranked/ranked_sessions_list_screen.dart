import 'package:flutter/material.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import 'ranked_sessions_screen.dart';
import '../../widgets/nav_entry_card.dart';

/// How many sessions are visible initially, and how many each "Load more"
/// tap adds.
const _kSessionPageSize = 6;

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

/// Full-screen sessions list, paginated
/// [_kSessionPageSize] at a time via a "Load more" button. Pass an empty
/// [sessions] list at Lifetime scope, where sessions were never offered (too
/// heavy at that scale, and RP resets each split anyway).
class RankedSessionsListScreen extends StatefulWidget {
  final List<RankedSession> sessions;
  final Future<void> Function() onRefresh;

  const RankedSessionsListScreen({
    super.key,
    required this.sessions,
    required this.onRefresh,
  });

  @override
  State<RankedSessionsListScreen> createState() =>
      _RankedSessionsListScreenState();
}

class _RankedSessionsListScreenState extends State<RankedSessionsListScreen> {
  int _visibleCount = _kSessionPageSize;

  @override
  Widget build(BuildContext context) {
    final visible = widget.sessions.take(_visibleCount).toList();
    final hasMore = _visibleCount < widget.sessions.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            if (visible.isNotEmpty) ...[
              const Text(
                'RECENT SESSIONS',
                style: AppTheme.cardTitle,
              ),
              const SizedBox(height: AppTheme.sm),
              for (final s in visible) ...[
                SessionRecapTile(
                  session: s,
                  onTap: () => openSessionHistory(context, s, widget.onRefresh),
                ),
                const SizedBox(height: AppTheme.sm),
              ],
              if (hasMore)
                Center(
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _visibleCount += _kSessionPageSize),
                    child: const Text('Load more'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
