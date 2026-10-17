import 'package:flutter/material.dart';
import '../../models/ranked_match.dart';
import '../../utils/ranked/ranked_period.dart';
import '../../utils/ranked/split_recap.dart';
import '../../widgets/nav_entry_card.dart';
import '../../widgets/share_card.dart';
import 'widgets/ranked_share_cards.dart';

/// The split (and week, when one is picked) on screen, for a card's title.
String recapScopeLabel(RankedView view) {
  final split = view.splits
      .where((s) => s.id == view.effectiveSplitId)
      .map((s) => s.displayName)
      .firstOrNull;
  final base = split ?? 'Ranked';
  return view.weekIndex >= 0 ? '$base Week ${view.weekIndex + 1}' : base;
}

/// A tappable row that opens the recap of the period on screen as a shareable
/// card. Hidden when there are no games to recap.
class RankedRecapEntry extends StatelessWidget {
  final List<RankedMatch> matches;
  final String scope;
  final String playerName;

  /// Whether the player is Apex Predator at the end of this period. Only known
  /// for the live period; a past one can't be told from today's cutoff.
  final bool isPredator;
  const RankedRecapEntry({
    super.key,
    required this.matches,
    required this.scope,
    required this.playerName,
    this.isPredator = false,
  });

  @override
  Widget build(BuildContext context) {
    final recap = splitRecap(matches);
    return NavEntryCard(
      icon: Icons.auto_awesome_outlined,
      title: 'Recap',
      onTap: recap.isEmpty
          ? () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No ranked games to recap yet.')),
            )
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ShareCardScreen(
                  title: 'Recap',
                  cardBuilder: (showName) => RecapShareCard(
                    recap: recap,
                    scope: scope,
                    playerName: showName ? playerName : null,
                    isPredator: isPredator,
                  ),
                ),
              ),
            ),
    );
  }
}
