import '../../constants/map_constants.dart' show isUnknownMapKey;
import 'ranked_aggregates.dart';

/// How much of a period's games a legend made up, in each of two periods.
typedef PickRateShift = ({String legend, double before, double after});

/// A map's RP per game in each of two periods.
typedef MapRpShift = ({String map, double before, double after});

/// Change in percentage points, to the whole point.
int pointsMoved(PickRateShift s) => ((s.after - s.before) * 100).round();

/// The legends whose share of games moved most from [before] to [after],
/// biggest move first. Moves that round to under a point are left out, and so
/// is everything when either period has no games.
List<PickRateShift> pickRateShifts(
  List<LegendBreakdown> before,
  List<LegendBreakdown> after, {
  int limit = 3,
}) {
  final gamesBefore = before.fold(0, (n, l) => n + l.games);
  final gamesAfter = after.fold(0, (n, l) => n + l.games);
  if (gamesBefore == 0 || gamesAfter == 0) return const [];
  final shareBefore = {for (final l in before) l.legend: l.games / gamesBefore};
  final shareAfter = {for (final l in after) l.legend: l.games / gamesAfter};
  final shifts = [
    for (final name in {...shareBefore.keys, ...shareAfter.keys})
      (
        legend: name,
        before: shareBefore[name] ?? 0.0,
        after: shareAfter[name] ?? 0.0,
      ),
  ].where((s) => pointsMoved(s) != 0).toList();
  shifts.sort((a, b) {
    final c = pointsMoved(b).abs().compareTo(pointsMoved(a).abs());
    return c != 0 ? c : a.legend.compareTo(b.legend);
  });
  return shifts.take(limit).toList();
}

/// The maps whose RP per game moved most from [before] to [after], biggest move
/// first. Only maps played at least [kMinGamesForInsight] times in both count,
/// since a few games say little about a map.
List<MapRpShift> mapRpShifts(
  List<MapBreakdown> before,
  List<MapBreakdown> after, {
  int limit = 3,
}) {
  final earlier = {
    for (final m in before)
      if (!isUnknownMapKey(m.mapKey) && m.games >= kMinGamesForInsight)
        m.mapKey: m,
  };
  final shifts = <MapRpShift>[
    for (final m in after)
      if (earlier[m.mapKey] case final was? when m.games >= kMinGamesForInsight)
        (map: m.displayName, before: was.avgRpPerGame, after: m.avgRpPerGame),
  ].where((s) => (s.after - s.before).abs() >= 0.05).toList();
  shifts.sort((a, b) {
    final c = (b.after - b.before).abs().compareTo((a.after - a.before).abs());
    return c != 0 ? c : a.map.compareTo(b.map);
  });
  return shifts.take(limit).toList();
}
