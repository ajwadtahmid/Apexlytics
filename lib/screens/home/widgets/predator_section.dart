import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../providers/predator_provider.dart';
import '../../../utils/navigation_utils.dart';
import '../../../utils/theme.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/summary_card.dart';
import '../predator_page.dart';
import 'summary_tile_skeleton.dart';

class PredatorSection extends ConsumerWidget {
  const PredatorSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(predatorProvider)
        .when(
          data: (result) {
            final count = result.data.rp.values.fold(
              0,
              (sum, p) => sum + p.totalMastersAndPreds,
            );
            return SummaryCard(
              leading: const FaIcon(
                FontAwesomeIcons.skull,
                color: AppTheme.accent,
                size: AppTheme.iconSizeMedium,
              ),
              title: 'Pred Cutoff',
              subtitle: '$count Masters & Preds across all platforms',
              onTap: () => context.pushPage(PredatorPage(data: result.data)),
            );
          },
          loading: () => const SummaryTileSkeleton(),
          error: (e, _) => ErrorCard(
            message: 'Pred Cutoff',
            compact: true,
            onRetry: () => ref.invalidate(predatorProvider),
          ),
        );
  }
}
