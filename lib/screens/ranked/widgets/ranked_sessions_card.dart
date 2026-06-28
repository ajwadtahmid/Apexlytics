import 'package:flutter/material.dart';
import '../../../models/ranked_match.dart';
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';
import '../ranked_sessions_screen.dart';

/// Overview session recap: one card showing the most recent play session in full
/// (tap to drill into its games), with a "Recent sessions" shortcut to the last
/// few sessions.
class RankedSessionsCard extends StatelessWidget {
  final List<RankedMatch> matches;
  final Future<void> Function() onRefresh;

  const RankedSessionsCard({
    super.key,
    required this.matches,
    required this.onRefresh,
  });

  /// How many sessions the "Recent sessions" screen lists.
  static const _recentCount = 5;

  @override
  Widget build(BuildContext context) {
    final sessions = sessionize(matches);
    if (sessions.isEmpty) return const SizedBox.shrink();

    final latest = sessions.first;
    final recent = sessions.take(_recentCount).toList();

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'LAST SESSION',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.muted,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (sessions.length > 1)
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RankedSessionsScreen(
                      sessions: recent,
                      onRefresh: onRefresh,
                    ),
                  )),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface2,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history, size: 13, color: AppTheme.accent),
                        SizedBox(width: 4),
                        Text(
                          'Recent sessions',
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.sm),
          // Tappable recap body — drills into the latest session's games.
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            onTap: () => openSessionHistory(context, latest, onRefresh),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SessionRecapBody(session: latest),
            ),
          ),
        ],
      ),
    );
  }
}
