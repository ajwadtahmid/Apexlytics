/// Minimum games before a legend/map qualifies for "best/worst" insights, so a
/// single lucky game doesn't crown a legend.
const int kMinGamesForInsight = 3;

/// The totals a ranked group (a legend, a map, a legend on a map) is judged on,
/// whatever it is a group of, and the averages they give. `BestMetric` reads
/// these to rank groups against each other.
abstract class RankedTally {
  final int games;
  final int totalRp; // Σ rpChange in the group

  /// Games with positive and with negative effective RP.
  final int wins;
  final int losses;

  final int totalKills;
  final int totalDamage;

  /// Games whose kills/damage upstream reported — the divisor for the averages.
  /// See `RankedSummary.killsGames`.
  final int killsGames;
  final int damageGames;

  const RankedTally({
    required this.games,
    required this.totalRp,
    required this.wins,
    required this.losses,
    required this.totalKills,
    required this.totalDamage,
    required this.killsGames,
    required this.damageGames,
  });

  double get avgRpPerGame => games == 0 ? 0 : totalRp / games;
  // Null, not 0, when no game reported the tracker: a zero would read as a
  // measured "no kills" rather than "not recorded".
  double? get avgKills => killsGames == 0 ? null : totalKills / killsGames;
  double? get avgDamage => damageGames == 0 ? null : totalDamage / damageGames;
  int get decidedGames => wins + losses;
  double get winRate => decidedGames == 0 ? 0 : wins / decidedGames;
}
