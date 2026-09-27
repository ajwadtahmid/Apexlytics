import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../constants/api_constants.dart';
import '../models/player_stats.dart';
import '../utils/formatting/format.dart';
import '../utils/formatting/platform_utils.dart';
import '../utils/formatting/rank_utils.dart' show rankAssetPath;
import '../utils/notifications.dart';
import '../utils/theme.dart';
import 'legend_icon.dart';
import 'status_dot.dart';
import 'surface_card.dart';

class PlayerInfoCard extends StatelessWidget {
  final PlayerStats stats;
  const PlayerInfoCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      radius: AppTheme.radiusLg,
      border: Border.all(color: AppTheme.accent.withAlpha(50)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: playerPresenceColor(stats)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stats.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                stats.presence,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Level ${stats.level}  •  ',
                style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
              SizedBox(
                width: 14,
                height: 14,
                // Source rank badges are several hundred px across; without
                // cacheWidth this decodes at full resolution to render a
                // 14×14 icon.
                child: Image.asset(
                  rankAssetPath(stats),
                  fit: BoxFit.contain,
                  cacheWidth: (14 * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                  errorBuilder: (ctx, err, trace) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${stats.rank}  •  ${formatNumber(stats.rankScore)} RP',
                style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (stats.uid.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'UID: ${stats.uid}',
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 2),
                      GestureDetector(
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: stats.uid),
                          );
                          if (context.mounted) {
                            context.showMessage(
                              'UID copied',
                              duration: const Duration(seconds: 2),
                            );
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.copy,
                            size: 12,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _PlatformBadge(platform: stats.platform),
              ],
            ),
            const SizedBox(height: 2),
          ],
          Row(
            children: [
              LegendIcon(legendName: stats.currentLegend, size: 14),
              const SizedBox(width: 4),
              Text(
                'Currently Tracking: ${stats.currentLegend}',
                style: const TextStyle(color: AppTheme.accent2, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.md),
          if (stats.trackers.isNotEmpty)
            ...stats.trackers
                .take(3)
                .map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            t.name,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatNumber(t.value),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                )
          else
            const Text(
              'No trackers equipped',
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

/// Small pill showing which platform [platform] (an `ApiConstants.platforms`
/// code) the player is on. PC can't be split into Steam/Origin — the API
/// this app reads from doesn't report a storefront, only the console/PC
/// code itself.
class _PlatformBadge extends StatelessWidget {
  final String platform;
  const _PlatformBadge({required this.platform});

  @override
  Widget build(BuildContext context) {
    final p = platformIconFor(platform);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: p.color.withAlpha(30),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(p.icon, color: p.color, size: 11),
          const SizedBox(width: 4),
          Text(
            ApiConstants.labelFor(platform),
            style: TextStyle(
              color: p.color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
