import '../../models/ranked_match.dart';
import 'ranked_aggregates.dart';

/// One point of the recap's climb: the player's RP after [game] games (0 is
/// where they started).
typedef JourneyPoint = ({int game, int rp});

/// A period's running RP, from where it started to where it ended, for the
/// recap's chart.
class Journey {
  /// The points to draw, oldest first, always including the start, the finish
  /// and the peak.
  final List<JourneyPoint> points;

  /// Where in [points] the highest RP was first reached.
  final int peakIndex;

  /// How many games the period had.
  final int games;

  const Journey({
    required this.points,
    required this.peakIndex,
    required this.games,
  });

  int get startRp => points.first.rp;
  int get finishRp => points.last.rp;
  int get peakRp => points[peakIndex].rp;

  /// Whether the peak is a point of its own, rather than the start or finish.
  bool get peakIsDistinct => peakIndex != 0 && peakIndex != points.length - 1;
}

/// The running RP across [matches], or null with no ranked games. Games that
/// don't count toward the stats are left out. Past [maxPoints] the line is
/// thinned evenly, keeping the start, the finish and the peak so they are never
/// lost.
Journey? recapJourney(List<RankedMatch> matches, {int maxPoints = 120}) {
  final games = rankedOnly(matches).reversed.toList(); // oldest first
  if (games.isEmpty) return null;
  final all = <JourneyPoint>[
    (game: 0, rp: games.first.cumulativeRp - games.first.rpChange),
    for (final (i, m) in games.indexed) (game: i + 1, rp: m.cumulativeRp),
  ];

  var peak = 0;
  for (var i = 1; i < all.length; i++) {
    if (all[i].rp > all[peak].rp) peak = i;
  }

  if (all.length <= maxPoints) {
    return Journey(points: all, peakIndex: peak, games: games.length);
  }
  final keep = <int>{0, all.length - 1, peak};
  for (var i = 0; i < maxPoints; i++) {
    keep.add((i * (all.length - 1) / (maxPoints - 1)).round());
  }
  final indexes = keep.toList()..sort();
  return Journey(
    points: [for (final i in indexes) all[i]],
    peakIndex: indexes.indexOf(peak),
    games: games.length,
  );
}
