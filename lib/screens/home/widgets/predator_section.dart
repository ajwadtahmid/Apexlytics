import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../constants/api_constants.dart';
import '../../../models/predator.dart';
import '../../../providers/predator_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/formatting/format.dart' show formatNumber;
import '../../../utils/navigation_utils.dart';
import '../../../utils/theme.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/summary_card.dart';
import '../predator_page.dart';
import 'summary_tile_skeleton.dart';

/// What the Pred Cutoff tile says. With a player set up, the cutoff for their
/// platform ("PC cutoff: 32,608 RP"); otherwise, or when that platform has no
/// reading, how many Masters and Preds there are across all of them.
String predatorTileSubtitle(PredatorResponse data, {String? platform}) {
  final own = platform == null ? null : data.forPlatform(platform);
  if (own != null && own.minRp > 0) {
    final label = ApiConstants.platformShortLabels[platform] ?? platform!;
    return '$label cutoff: ${formatNumber(own.minRp)} RP';
  }
  final count = data.rp.values.fold(
    0,
    (sum, p) => sum + p.totalMastersAndPreds,
  );
  return '${formatNumber(count)} Masters & Preds across all platforms';
}

class PredatorSection extends ConsumerWidget {
  const PredatorSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The selected profile's platform, once a player is set up.
    final platform = ref.watch(
      playerSettingsProvider.select(
        (s) => s.name.isNotEmpty ? s.platform : null,
      ),
    );
    return ref
        .watch(predatorProvider)
        .when(
          data: (result) {
            return SummaryCard(
              leading: const FaIcon(
                FontAwesomeIcons.skull,
                color: AppTheme.accent,
                size: AppTheme.iconSizeMedium,
              ),
              title: 'Pred Cutoff',
              subtitle: predatorTileSubtitle(result.data, platform: platform),
              onTap: () => context.pushPage(
                PredatorPage(data: result.data, yourPlatform: platform),
              ),
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
