import 'package:flutter/material.dart';
import '../../utils/ranked/ranked_aggregates.dart';
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';
import 'ranked_sessions_screen.dart';

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

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RankedSessionsListScreen(
              sessions: sessions,
              onRefresh: onRefresh,
            ),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppTheme.md),
          child: Row(
            children: [
              Icon(Icons.timeline, size: 18, color: AppTheme.accent),
              SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  'Sessions',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppTheme.muted),
            ],
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.muted,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
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
