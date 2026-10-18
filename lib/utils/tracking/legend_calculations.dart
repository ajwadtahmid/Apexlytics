import '../../constants/tracker_constants.dart';
import '../../models/player_stats.dart';
import '../formatting/format.dart';
import 'legend_tracker_logic.dart';

/// A figure worked out from a legend's trackers, ready to show.
typedef LegendCalculation = ({String label, String value});

/// What can be worked out from [trackers]: each figure appears only when the
/// trackers it needs are there, and never divides by zero. Trackers are matched
/// by exact display name, case aside, so "BR Kills" never catches a longer name
/// that merely contains it.
List<LegendCalculation> legendCalculations(List<LegendTracker> trackers) {
  int? valueOf(String name) =>
      findTracker(trackers, (t) => t.displayName.toLowerCase() == name)?.value;

  final kills = valueOf(TrackerKeys.brKills);
  final wins = valueOf(TrackerKeys.brWins);
  final games = valueOf(TrackerKeys.brGamesPlayed);
  final damage = valueOf(TrackerKeys.brDamage);
  final revives = valueOf(TrackerKeys.brRevives);
  final top3 = valueOf(TrackerKeys.brTop3);
  final killLeader = valueOf(TrackerKeys.brKillsAsKillLeader);

  final hasKills = kills != null && kills > 0;
  final hasGames = games != null && games > 0;
  return [
    if (hasKills && damage != null)
      (label: 'Damage per Kill', value: formatNumber((damage / kills).round())),
    if (kills != null && hasGames)
      (label: 'Avg Kills per Game', value: (kills / games).toStringAsFixed(1)),
    if (wins != null && hasGames)
      (label: 'Win Rate', value: '${(wins / games * 100).toStringAsFixed(1)}%'),
    if (revives != null && hasGames)
      (label: 'Revive Rate', value: (revives / games).toStringAsFixed(2)),
    if (top3 != null && hasGames)
      (
        label: 'Top 3 Placement %',
        value: '${(top3 / games * 100).toStringAsFixed(1)}%',
      ),
    if (killLeader != null && hasKills)
      (
        label: 'Kills as Kill Leader %',
        value: '${(killLeader / kills * 100).toStringAsFixed(1)}%',
      ),
  ];
}
