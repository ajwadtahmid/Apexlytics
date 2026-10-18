import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/recap_tiles_provider.dart';
import '../../utils/ranked/recap_tiles.dart';
import '../../utils/ranked/split_recap.dart';
import '../../utils/theme.dart';
import '../../widgets/share_card.dart';
import 'widgets/ranked_share_cards.dart';

/// The recap as a card to share, with the choice of which tiles go on it. The
/// choice is kept between visits; the win rate and the win streak are there to
/// be asked for.
class RankedRecapShareScreen extends ConsumerWidget {
  final SplitRecap recap;
  final String scope;
  final String playerName;
  final bool isPredator;

  /// See [RecapShareCard.periodPhrase].
  final String periodPhrase;

  const RankedRecapShareScreen({
    super.key,
    required this.recap,
    required this.scope,
    required this.playerName,
    this.isPredator = false,
    this.periodPhrase = 'this split',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(recapTilesProvider);
    final available = availableRecapTiles(recap);
    final shown = shownRecapTiles(chosen, available);

    return Scaffold(
      appBar: AppBar(title: const Text('Recap card')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.md),
          children: [
            ShareCardPanel(
              cardBuilder: (showName) => RecapShareCard(
                recap: recap,
                scope: scope,
                playerName: showName ? playerName : null,
                isPredator: isPredator,
                tiles: shown,
                periodPhrase: periodPhrase,
              ),
              controls: _TilePicker(
                available: available,
                shown: shown,
                onToggle: (tile) => ref
                    .read(recapTilesProvider.notifier)
                    .toggle(tile, available),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A chip for each tile the card can show: lit when it is on the card. The last
/// [kMinRecapTiles] can't be switched off.
class _TilePicker extends StatelessWidget {
  final Set<RecapTile> available;
  final List<RecapTile> shown;
  final ValueChanged<RecapTile> onToggle;
  const _TilePicker({
    required this.available,
    required this.shown,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final atLeast = shown.length <= kMinRecapTiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Show on the card',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        const Text('Keep at least two.', style: AppTheme.caption),
        const SizedBox(height: AppTheme.sm),
        Wrap(
          spacing: AppTheme.sm,
          runSpacing: AppTheme.xs,
          children: [
            for (final tile in RecapTile.values)
              if (available.contains(tile))
                FilterChip(
                  label: Text(tile.label),
                  selected: shown.contains(tile),
                  showCheckmark: false,
                  selectedColor: AppTheme.accent.withAlpha(60),
                  // Switching off the last two is refused: left disabled.
                  onSelected: shown.contains(tile) && atLeast
                      ? null
                      : (_) => onToggle(tile),
                ),
          ],
        ),
      ],
    );
  }
}
