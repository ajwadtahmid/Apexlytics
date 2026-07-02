import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../constants/rank_constants.dart';
import '../../../providers/predator_provider.dart';
import '../../../providers/rank_goal_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/formatting/format.dart' show formatNumber;
import '../../../utils/formatting/rank_utils.dart' show rankAssetPathByTier;
import '../../../utils/ranked/ranked_aggregates.dart';
import '../../../utils/theme.dart';
import '../../../widgets/surface_card.dart';

class RankedSummaryHeader extends ConsumerWidget {
  final RankedSummary summary;
  final String uid;

  const RankedSummaryHeader({
    super.key,
    required this.summary,
    required this.uid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netPositive = summary.netRp >= 0;
    final netColor = netPositive ? AppTheme.green : AppTheme.red;

    final goalIndex = ref.watch(rankGoalProvider(uid));
    final predatorRp = _predatorRp(ref);
    final progress = summary.games == 0
        ? null
        : RankProgress.from(summary,
            goalIndex: goalIndex, predatorRp: predatorRp);

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Prefer the locally-derived, Predator-aware badge over the raw
              // API image: the latter reflects whatever tier the last match
              // was tagged with, which doesn't track the live Predator cutoff.
              if (progress != null) ...[
                Image.asset(
                  rankAssetPathByTier(progress.isPredator, progress.currentIndex),
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(width: 36),
                ),
                const SizedBox(width: AppTheme.sm),
              ] else if (summary.latestRankImg.isNotEmpty) ...[
                CachedNetworkImage(
                  imageUrl: summary.latestRankImg,
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) => const SizedBox(width: 36),
                ),
                const SizedBox(width: AppTheme.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current RP',
                      style: TextStyle(color: AppTheme.muted, fontSize: 11),
                    ),
                    Text(
                      formatNumber(summary.currentRp),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.sm),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: netColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Text(
                  '${netPositive ? '+' : ''}${formatNumber(summary.netRp)} RP',
                  style: TextStyle(
                    color: netColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: AppTheme.sm),
            _ProgressBars(progress: progress),
            // No goal to set once you're already the top of the ladder.
            if (!progress.isPredator) ...[
              const Divider(color: AppTheme.surface2, height: AppTheme.lg),
              _GoalFooter(uid: uid, progress: progress),
            ],
          ],
        ],
      ),
    );
  }

  int? _predatorRp(WidgetRef ref) {
    final platform = ref.watch(
        playerSettingsProvider.select((s) => s.platform));
    final async = ref.watch(predatorProvider);
    final data = async.asData?.value.data;
    return data?.forPlatform(platform)?.minRp;
  }
}

// ── Next-division progress ─────────────────────────────────────────────────

class _ProgressBars extends StatelessWidget {
  final RankProgress progress;
  const _ProgressBars({required this.progress});

  @override
  Widget build(BuildContext context) {
    final next = progress.next;
    if (next == null) {
      return Text(
        progress.isPredator
            ? 'Apex Predator — top of the ladder.'
            : 'Top of the ladder — Apex Predator cutoff unavailable.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: progress.isPredator ? kPredatorColor : AppTheme.muted,
          fontSize: 12,
          height: 1.3,
          fontWeight: progress.isPredator ? FontWeight.w600 : FontWeight.normal,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              progress.current.label,
              style: TextStyle(
                color: progress.current.color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              next.label,
              style: TextStyle(
                color: next.color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: progress.progressToNext,
            minHeight: 6,
            backgroundColor: AppTheme.surface2,
            valueColor: AlwaysStoppedAnimation(progress.current.color),
          ),
        ),
        const SizedBox(height: AppTheme.sm),
        SizedBox(
          width: double.infinity,
          child: _estimateWidget(
              progress.rpTo(next), progress.gamesTo(next), next),
        ),
      ],
    );
  }
}

// ── Goal footer ────────────────────────────────────────────────────────────

class _GoalFooter extends StatelessWidget {
  final String uid;
  final RankProgress progress;
  const _GoalFooter({required this.uid, required this.progress});

  @override
  Widget build(BuildContext context) {
    final goal = progress.goal;
    if (goal == null) {
      return Row(
        children: [
          const Expanded(
            child: Text(
              'No goal set',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
          _GoalButton(
            hasGoal: false,
            onTap: () => _openGoalSheet(context),
          ),
        ],
      );
    }
    final rpRemaining = progress.rpTo(goal);
    final games = progress.gamesTo(goal);
    return Row(
      children: [
        Image.asset(
          progress.isPredatorGoal
              ? 'assets/ranks/apex_predator.webp'
              : goal.assetPath,
          width: 24,
          height: 24,
          errorBuilder: (_, _, _) => Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: goal.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: AppTheme.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    if (rpRemaining > 0) ...[
                      TextSpan(text: '${formatNumber(rpRemaining)} RP to '),
                      TextSpan(
                        text: goal.label,
                        style: TextStyle(color: goal.color),
                      ),
                    ] else ...[
                      TextSpan(
                        text: goal.label,
                        style: TextStyle(color: goal.color),
                      ),
                      const TextSpan(text: ' reached'),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _pacePhrase(games, progress.avgRpPerGame),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppTheme.sm),
        _GoalButton(
          hasGoal: true,
          onTap: () => _openGoalSheet(context),
        ),
      ],
    );
  }

  Future<void> _openGoalSheet(BuildContext context) async {
    final ladderOptions = [
      for (var i = progress.currentIndex + 1; i < kRankLadder.length; i++) i,
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Consumer(builder: (context, ref, _) {
            void choose(int? index) {
              ref.read(rankGoalProvider(uid).notifier).setGoal(index);
              Navigator.of(sheetCtx).pop();
            }

            final predatorRp = _livePredatorRp(ref);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.md, vertical: AppTheme.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Set rank goal',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (progress.goalIndex != null)
                  ListTile(
                    leading: const Icon(Icons.not_interested,
                        color: AppTheme.muted),
                    title: const Text('No goal',
                        style: TextStyle(color: AppTheme.textPrimary)),
                    onTap: () => choose(null),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final i in ladderOptions)
                        ListTile(
                          leading: Image.asset(
                            kRankLadder[i].assetPath,
                            width: 28,
                            height: 28,
                            errorBuilder: (_, _, _) => Icon(
                                Icons.military_tech,
                                color: kRankLadder[i].color),
                          ),
                          title: Text(
                            kRankLadder[i].label,
                            style:
                                const TextStyle(color: AppTheme.textPrimary),
                          ),
                          trailing: Text(
                            '${formatNumber(kRankLadder[i].rp)} RP',
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 12),
                          ),
                          selected: i == progress.goalIndex,
                          onTap: () => choose(i),
                        ),
                      if (predatorRp != null && predatorRp > 0)
                        ListTile(
                          leading: Image.asset(
                            'assets/ranks/apex_predator.webp',
                            width: 24,
                            height: 24,
                            errorBuilder: (_, _, _) => const Icon(
                                Icons.military_tech,
                                color: kPredatorColor),
                          ),
                          title: const Text(
                            kApexPredatorRank,
                            style: TextStyle(color: kPredatorColor),
                          ),
                          trailing: Text(
                            '${formatNumber(predatorRp)} RP',
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 12),
                          ),
                          selected: progress.isPredatorGoal,
                          onTap: () => choose(kPredatorGoalIndex),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }),
        );
      },
    );
  }

  int? _livePredatorRp(WidgetRef ref) {
    final platform =
        ref.watch(playerSettingsProvider.select((s) => s.platform));
    final async = ref.watch(predatorProvider);
    final data = async.asData?.value.data;
    return data?.forPlatform(platform)?.minRp;
  }
}

class _GoalButton extends StatelessWidget {
  final bool hasGoal;
  final VoidCallback onTap;
  const _GoalButton({required this.hasGoal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hasGoal ? Icons.flag : Icons.flag_outlined,
                size: 13, color: AppTheme.accent),
            const SizedBox(width: 4),
            Text(
              hasGoal ? 'Edit goal' : 'Set goal',
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

Widget _estimateWidget(int rp, int? games, RankDivision target) {
  const white = TextStyle(
      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600);
  const muted = TextStyle(color: AppTheme.muted, fontSize: 12);
  final List<InlineSpan> spans;
  if (games == null) {
    spans = const [TextSpan(text: 'Losing RP — no estimate', style: muted)];
  } else if (games == 0) {
    spans = [
      const TextSpan(text: 'Within reach of ', style: muted),
      TextSpan(
        text: target.label,
        style: TextStyle(
            color: target.color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ];
  } else {
    spans = [
      TextSpan(text: '${formatNumber(rp)} RP ', style: white),
      TextSpan(
        text: '(~$games ${games == 1 ? 'game' : 'games'}) ',
        style: muted,
      ),
      const TextSpan(text: 'to ', style: muted),
      TextSpan(
        text: target.label,
        style: TextStyle(
            color: target.color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ];
  }
  return Text.rich(
    TextSpan(children: spans),
    textAlign: TextAlign.center,
  );
}

String _pacePhrase(int? games, double avg) {
  if (games == null) return 'No estimate at this pace';
  if (games == 0) return 'Within reach';
  final sign = avg >= 0 ? '+' : '';
  return '~$games ${games == 1 ? 'game' : 'games'} at $sign${avg.toStringAsFixed(1)} RP/game';
}

