import '../../models/ranked_match.dart';

/// Fewest qualifying games a legend needs before its average is shown as a
/// comparison point — below this, one big game swings the average too much.
const int kBaselineMinGames = 5;

/// A legend's average kills and damage over [LegendBaseline.games] games, for
/// judging how one match compares. A field is null when fewer than
/// [kBaselineMinGames] games reported that stat.
class LegendBaseline {
  final double? avgKills;
  final double? avgDamage;
  const LegendBaseline({this.avgKills, this.avgDamage});

  bool get isEmpty => avgKills == null && avgDamage == null;
}

/// The average to compare [match] against: the same legend in the same mode
/// (ranked vs pubs), from [pool], skipping outlier and excluded games and any
/// game that didn't report the stat. [match] itself counts when it qualifies.
/// Null when neither stat has enough games.
LegendBaseline? legendBaselineFor(RankedMatch match, Iterable<RankedMatch> pool) {
  var killSum = 0;
  var killN = 0;
  var dmgSum = 0;
  var dmgN = 0;
  for (final m in pool) {
    if (m.legend != match.legend || m.isRanked != match.isRanked) continue;
    if (m.excluded || m.isRankedOutlier) continue;
    final k = m.kills;
    if (k != null) {
      killSum += k;
      killN++;
    }
    final d = m.damage;
    if (d != null) {
      dmgSum += d;
      dmgN++;
    }
  }
  final baseline = LegendBaseline(
    avgKills: killN >= kBaselineMinGames ? killSum / killN : null,
    avgDamage: dmgN >= kBaselineMinGames ? dmgSum / dmgN : null,
  );
  return baseline.isEmpty ? null : baseline;
}
