import 'split_recap.dart';

/// A figure the recap card can show as a tile. The card lists them in this
/// order, two to a row.
enum RecapTile {
  games('Games'),
  peakRp('Peak RP'),
  kills('Kills'),
  damage('Damage'),
  bestSession('Best session'),
  timePlayed('Time played'),
  bestLegend('Best legend'),
  bestMap('Best map'),
  winRate('Win rate'),
  rpPerGame('Avg RP');

  final String label;
  const RecapTile(this.label);

  /// Shown until the player says otherwise. The win rate and average RP are
  /// there to be asked for.
  bool get onByDefault => this != winRate && this != rpPerGame;
}

/// The fewest tiles the card can have.
const int kMinRecapTiles = 2;

/// The tiles shown when nothing has been chosen.
Set<RecapTile> get defaultRecapTiles => {
  for (final t in RecapTile.values)
    if (t.onByDefault) t,
};

/// The tiles that have something to show for [recap]: no best legend or map when
/// none played enough games, and no best session without one.
Set<RecapTile> availableRecapTiles(SplitRecap recap) => {
  for (final t in RecapTile.values)
    if (switch (t) {
      RecapTile.bestLegend => recap.bestLegend != null,
      RecapTile.bestMap => recap.bestMap != null,
      RecapTile.bestSession => recap.bestSession != null,
      _ => true,
    })
      t,
};

/// The tiles to draw: those [chosen] that are [available], in card order. When
/// that leaves fewer than [kMinRecapTiles] (a choice made for another period)
/// the defaults stand in.
List<RecapTile> shownRecapTiles(
  Set<RecapTile> chosen,
  Set<RecapTile> available,
) {
  List<RecapTile> pick(Set<RecapTile> from) => [
    for (final t in RecapTile.values)
      if (from.contains(t) && available.contains(t)) t,
  ];
  final shown = pick(chosen);
  return shown.length >= kMinRecapTiles ? shown : pick(defaultRecapTiles);
}
