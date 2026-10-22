import 'package:flutter/material.dart';
import '../../models/ranked_match.dart';
import '../../utils/ranked/ranked_aggregates.dart' show rankedOnly;
import '../../utils/ranked/ranked_period.dart';
import '../../widgets/nav_entry_card.dart';
import 'ranked_recap_screen.dart';

/// The split (and week, when one is picked and [week] is true) on screen, for a
/// card's title.
String recapScopeLabel(RankedView view, {bool week = true}) {
  final split = view.splits
      .where((s) => s.id == view.effectiveSplitId)
      .map((s) => s.displayName)
      .firstOrNull;
  final base = split ?? 'Ranked';
  return week && view.weekIndex >= 0
      ? '$base Week ${view.weekIndex + 1}'
      : base;
}

/// Where the RP netted was made: "in Week 3" when a week is picked, otherwise
/// "this split".
String recapPeriodPhrase(RankedView view) =>
    view.weekIndex >= 0 ? 'in Week ${view.weekIndex + 1}' : 'this split';

/// A tappable row that opens the recap of the period on screen as a shareable
/// card. Hidden when there are no games to recap.
class RankedRecapEntry extends StatelessWidget {
  final List<RankedMatch> matches;
  final String scope;
  final String playerName;

  /// Whether the player is Apex Predator at the end of this period. Only known
  /// for the live period; a past one can't be told from today's cutoff.
  final bool isPredator;

  /// See [recapPeriodPhrase].
  final String periodPhrase;

  const RankedRecapEntry({
    super.key,
    required this.matches,
    required this.scope,
    required this.playerName,
    this.isPredator = false,
    this.periodPhrase = 'this split',
  });

  @override
  Widget build(BuildContext context) {
    return NavEntryCard(
      icon: Icons.auto_awesome_outlined,
      title: 'Recap',
      onTap: rankedOnly(matches).isEmpty
          ? () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No ranked games to recap yet.')),
            )
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RankedRecapScreen(
                  matches: matches,
                  scope: scope,
                  playerName: playerName,
                  isPredator: isPredator,
                  periodPhrase: periodPhrase,
                ),
              ),
            ),
    );
  }
}
