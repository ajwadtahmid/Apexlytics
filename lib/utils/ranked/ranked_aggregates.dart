/// Pure aggregation functions over a list of [RankedMatch].
///
/// Everything here is deterministic and widget-free so it can be unit-tested in
/// isolation. The UI layer (Phase 2+) consumes these view models directly.
library;

import '../../constants/legend_constants.dart';
import '../../constants/rank_constants.dart';
import '../../constants/map_constants.dart';
import '../../models/ranked_match.dart';
import '../formatting/rank_utils.dart'
    show isApexPredatorRp, rankIndex, usablePredatorCutoff;
import 'best_metric.dart';
import 'ranked_tally.dart';

export 'ranked_tally.dart';

/// Default gap that separates one play session from the next.
const Duration kSessionGap = Duration(hours: 2);

/// Returns only ranked (Battle Royale) matches that count toward the stats —
/// not hand-excluded, not auto-excluded for an implausible RP swing — newest
/// first.
List<RankedMatch> rankedOnly(List<RankedMatch> all) {
  final list = all.where((m) => m.isRanked && m.countsTowardStats).toList()
    ..sort((a, b) => b.endTime.compareTo(a.endTime));
  return list;
}

// ── Shared accumulator ──────────────────────────────────────────────────────

/// One definition of a ranked group's totals. The Dart path feeds it matches
/// ([add]), the SQL path feeds it aggregate rows ([addRow]), and both build
/// their view models from it so the two paths can't drift.
class RankedAgg {
  int games = 0;
  int rp = 0;
  int kills = 0;
  int damage = 0;

  /// Games whose kills/damage upstream reported — the averages' divisors.
  int killsGames = 0;
  int damageGames = 0;

  int length = 0;
  int wins = 0;
  int losses = 0;

  void add(RankedMatch m) {
    games++;
    final effective = m.effectiveRpChange;
    rp += effective;
    final k = m.kills;
    if (k != null) {
      kills += k;
      killsGames++;
    }
    final d = m.damage;
    if (d != null) {
      damage += d;
      damageGames++;
    }
    length += m.lengthSecs;
    if (effective > 0) {
      wins++;
    } else if (effective < 0) {
      losses++;
    }
  }

  void addAll(Iterable<RankedMatch> matches) => matches.forEach(add);

  /// Adds one SQL aggregate row (`games`, `kills`, `damage`, `kills_games`,
  /// `damage_games`, `length_secs`, `net_rp`, `wins`, `losses`).
  void addRow(Map<String, Object?> r) {
    int n(String key) => (r[key] as num).toInt();
    games += n('games');
    rp += n('net_rp');
    kills += n('kills');
    damage += n('damage');
    killsGames += n('kills_games');
    damageGames += n('damage_games');
    length += n('length_secs');
    wins += n('wins');
    losses += n('losses');
  }

  void addAllRows(Iterable<Map<String, Object?>> rows) => rows.forEach(addRow);

  RankedSummary toSummary({int currentRp = 0, String latestRankImg = ''}) =>
      games == 0
      ? RankedSummary.empty
      : RankedSummary(
          games: games,
          netRp: rp,
          currentRp: currentRp,
          latestRankImg: latestRankImg,
          totalKills: kills,
          totalDamage: damage,
          killsGames: killsGames,
          damageGames: damageGames,
          totalLengthSecs: length,
          wins: wins,
          losses: losses,
        );

  LegendBreakdown toLegend(String legend) => LegendBreakdown(
    legend: legend,
    games: games,
    totalRp: rp,
    totalKills: kills,
    totalDamage: damage,
    killsGames: killsGames,
    damageGames: damageGames,
    totalLengthSecs: length,
    wins: wins,
    losses: losses,
  );

  MapBreakdown toMap(String mapKey, String displayName) => MapBreakdown(
    mapKey: mapKey,
    displayName: displayName,
    games: games,
    totalRp: rp,
    totalKills: kills,
    totalDamage: damage,
    killsGames: killsGames,
    damageGames: damageGames,
    totalLengthSecs: length,
    wins: wins,
    losses: losses,
  );

  LegendMapCell toCell(String legend, String mapName) => LegendMapCell(
    legend: legend,
    mapName: mapName,
    games: games,
    totalRp: rp,
    wins: wins,
    losses: losses,
    totalKills: kills,
    killsGames: killsGames,
    totalDamage: damage,
    damageGames: damageGames,
  );
}

// ── Window summary (drives the Overview stat row) ───────────────────────────

class RankedSummary {
  final int games;
  final int netRp; // Σ rpChange across the window
  final int currentRp; // cumulativeRp of the most recent match
  final String latestRankImg;
  final int totalKills;
  final int totalDamage;

  /// Games whose kills/damage upstream actually reported. Averages divide by
  /// these rather than [games]: a match carrying no tracker is unknown, not
  /// zero. A reported 0 is a real bad game and counts normally.
  final int killsGames;
  final int damageGames;

  final int totalLengthSecs;
  final int wins; // games with positive effective RP
  final int losses; // games with negative effective RP

  const RankedSummary({
    required this.games,
    required this.netRp,
    required this.currentRp,
    required this.latestRankImg,
    required this.totalKills,
    required this.totalDamage,
    required this.killsGames,
    required this.damageGames,
    required this.totalLengthSecs,
    required this.wins,
    required this.losses,
  });

  double get avgRpPerGame => games == 0 ? 0 : netRp / games;
  // Null, not 0, when no game reported the tracker: a zero would read as a
  // measured "no kills" rather than "not recorded".
  double? get avgKills => killsGames == 0 ? null : totalKills / killsGames;
  double? get avgDamage => damageGames == 0 ? null : totalDamage / damageGames;
  double get avgGameLengthSecs => games == 0 ? 0 : totalLengthSecs / games;

  /// Games that count toward win rate: wins + losses. Excludes RP-neutral games
  /// (pubs and neutralized end-of-split reset artifacts), so it can be < [games].
  int get decidedGames => wins + losses;

  /// Fraction of decided games won (0..1); 0 when no decided games.
  double get winRate => decidedGames == 0 ? 0 : wins / decidedGames;

  static const empty = RankedSummary(
    games: 0,
    netRp: 0,
    currentRp: 0,
    latestRankImg: '',
    totalKills: 0,
    totalDamage: 0,
    killsGames: 0,
    damageGames: 0,
    totalLengthSecs: 0,
    wins: 0,
    losses: 0,
  );
}

/// Assumes [matches] is already ranked-only filtered (the caller owns that via
/// [rankedOnly]/`matchesInSplit`) — re-filtering on every call was pure waste.
///
/// [currentRpFrom] supplies the newest match for `currentRp`/`latestRankImg`
/// when it should include matches [matches] leaves out (excluded ones still
/// moved the player's running RP, and so did games before an empty window).
RankedSummary summarize(
  List<RankedMatch> matches, {
  Iterable<RankedMatch>? currentRpFrom,
}) {
  if (matches.isEmpty) {
    RankedMatch? last;
    for (final m in currentRpFrom ?? const <RankedMatch>[]) {
      if (last == null || m.endTime.isAfter(last.endTime)) last = m;
    }
    if (last == null) return RankedSummary.empty;
    return RankedSummary(
      games: 0,
      netRp: 0,
      currentRp: last.cumulativeRp,
      latestRankImg: last.rankImg,
      totalKills: 0,
      totalDamage: 0,
      killsGames: 0,
      damageGames: 0,
      totalLengthSecs: 0,
      wins: 0,
      losses: 0,
    );
  }

  // Find the newest match for currentRp/rankImg without a full sort.
  var newest = matches.first;
  for (final m in currentRpFrom ?? const <RankedMatch>[]) {
    if (m.endTime.isAfter(newest.endTime)) newest = m;
  }
  final agg = RankedAgg();
  for (final m in matches) {
    agg.add(m);
    if (m.endTime.isAfter(newest.endTime)) newest = m;
  }
  return agg.toSummary(
    currentRp: newest.cumulativeRp,
    latestRankImg: newest.rankImg,
  );
}

// ── Legend breakdown ────────────────────────────────────────────────────────

class LegendBreakdown extends RankedTally {
  final String legend;
  final int totalLengthSecs;

  const LegendBreakdown({
    required this.legend,
    required super.games,
    required super.totalRp,
    required super.totalKills,
    required super.totalDamage,
    required super.killsGames,
    required super.damageGames,
    required this.totalLengthSecs,
    required super.wins,
    required super.losses,
  });

  double get avgLengthSecs => games == 0 ? 0 : totalLengthSecs / games;
}

/// Per-legend breakdown, sorted by total RP contribution (descending).
/// Assumes [matches] is already ranked-only filtered.
///
/// Grouped by [canonicalLegendName], not the raw [RankedMatch.legend]: a case
/// variant upstream sends for one player (e.g. `"bloodhound"` vs
/// `"Bloodhound"`) would otherwise split one legend into two
/// identically-labelled rows — the same problem [mapBreakdowns] already
/// solves for map keys via [canonicalMapKey]. [canonicalLegendName] returns
/// the display name directly (unlike a map's raw representative key), so
/// each group's [LegendBreakdown.legend] is always the canonical name — a
/// drill-down still has to match case-insensitively against the raw value on
/// each [RankedMatch] (see [RankedHistoryStore.matchesForLegend]), since a
/// match's own `legend` field is left as upstream sent it.
List<LegendBreakdown> legendBreakdowns(List<RankedMatch> matches) {
  final byLegend = <String, List<RankedMatch>>{};
  for (final m in matches) {
    byLegend.putIfAbsent(canonicalLegendName(m.legend), () => []).add(m);
  }
  return [
    for (final e in byLegend.entries)
      (RankedAgg()..addAll(e.value)).toLegend(e.key),
  ]..sort(byTotalRpThenName);
}

/// Deterministic tie-break for an exact [LegendBreakdown.totalRp] tie:
/// alphabetical by legend name. Shared with [RankedHistoryStore]'s SQL
/// counterpart ([RankedHistoryStore.legendBreakdownsFor]), which builds its
/// pre-sort map in a different (SQLite-determined) iteration order — without
/// a shared, deterministic tie-break the two paths could render the same
/// tied pair in a different order.
int byTotalRpThenName(LegendBreakdown a, LegendBreakdown b) {
  final rp = b.totalRp.compareTo(a.totalRp);
  return rp != 0 ? rp : a.legend.compareTo(b.legend);
}

// ── Map breakdown ───────────────────────────────────────────────────────────

class MapBreakdown extends RankedTally {
  final String mapKey;
  final String displayName;
  final int totalLengthSecs;

  const MapBreakdown({
    required this.mapKey,
    required this.displayName,
    required super.games,
    required super.totalRp,
    required super.totalKills,
    required super.totalDamage,
    required super.killsGames,
    required super.damageGames,
    required this.totalLengthSecs,
    required super.wins,
    required super.losses,
  });

  double get avgLengthSecs => games == 0 ? 0 : totalLengthSecs / games;
}

/// Per-map breakdown, sorted by games played (descending).
/// Assumes [matches] is already ranked-only filtered.
///
/// Grouped by [canonicalMapKey], not the raw `map_key`: `edistrict` and
/// `edistrict_rotation` name the same map (see [kBattleRoyaleMaps]), and
/// grouping on the raw key would split one map into several
/// identically-labelled rows. Matches the canonicalization
/// [legendMapBreakdowns] already applies. Each group's [MapBreakdown.mapKey]
/// is one representative raw key from that group — drill-down callers must
/// resolve every variant back via [battleRoyaleMapKeyVariants] (or an equivalent
/// [canonicalMapKey] comparison), not an exact match on that key.
List<MapBreakdown> mapBreakdowns(List<RankedMatch> matches) {
  final byMap = <String, List<RankedMatch>>{};
  final representativeKey = <String, String>{};
  for (final m in matches) {
    final canonical = canonicalMapKey(m.mapKey);
    byMap.putIfAbsent(canonical, () => []).add(m);
    representativeKey.putIfAbsent(canonical, () => m.mapKey);
  }
  return [
    for (final e in byMap.entries)
      (RankedAgg()..addAll(e.value)).toMap(
        representativeKey[e.key]!,
        battleRoyaleMapName(representativeKey[e.key]!),
      ),
  ]..sort(byGamesThenName);
}

/// Deterministic tie-break for an exact [MapBreakdown.games] tie: alphabetical
/// by display name. See [byTotalRpThenName] for why this needs to be shared
/// with the SQL path ([RankedHistoryStore.mapBreakdownsFor]).
int byGamesThenName(MapBreakdown a, MapBreakdown b) {
  final g = b.games.compareTo(a.games);
  return g != 0 ? g : a.displayName.compareTo(b.displayName);
}

// ── Legend × Map matrix ──────────────────────────────────────────────────────
//
// A standalone drill-down, self-contained on purpose: it touches no other
// aggregate here and nothing else calls it, so it stays a one-function,
// one-widget feature.

class LegendMapCell extends RankedTally {
  final String legend;
  final String mapName;

  // Everything but games and RP is left at 0 by a cell made from only those,
  // such as the grid's totals (see `matrixTotals`), which nothing ranks.
  const LegendMapCell({
    required this.legend,
    required this.mapName,
    required super.games,
    required super.totalRp,
    super.wins = 0,
    super.losses = 0,
    super.totalKills = 0,
    super.killsGames = 0,
    super.totalDamage = 0,
    super.damageGames = 0,
  });
}

/// Per (legend, map) breakdown, restricted to legends in [kLegends] and maps in
/// [kBattleRoyaleMaps] — a raw or "Unknown" value from either is dropped rather than
/// shown as its own row/column. Both names are canonicalized through their
/// constant lookup, so map-key variants that mean the same map (e.g.
/// `worlds_edge` and `worlds_edge_rotation`) land in one cell. Only pairs with
/// at least one game appear — there is no zero-filled grid to prune from.
/// Assumes [matches] is already ranked-only filtered.
List<LegendMapCell> legendMapBreakdowns(List<RankedMatch> matches) {
  final byPair = <(String, String), List<RankedMatch>>{};
  for (final m in matches) {
    final legend = legendInfo(m.legend)?.name;
    final mapName = battleRoyaleMapInfo(m.mapKey)?.name;
    if (legend == null || mapName == null) continue;
    byPair.putIfAbsent((legend, mapName), () => []).add(m);
  }

  return [
    for (final entry in byPair.entries)
      (RankedAgg()..addAll(entry.value)).toCell(entry.key.$1, entry.key.$2),
  ];
}

/// One map's record and the legends that do best and worst on it.
class MapLegendInsight {
  final String mapName;
  final int games;
  final int totalRp;

  /// The legend with the highest RP per game on this map among those with at
  /// least [kMinGamesForInsight] games there; null when none has played enough.
  final LegendMapCell? best;

  /// The one with the lowest, among the same legends. Null unless there are two
  /// or more of them and it does worse than [best].
  final LegendMapCell? worst;

  /// How many legends have enough games here, and a figure for the measure, to
  /// be compared.
  final int qualified;

  /// How many have enough games here, whether or not they have a figure for the
  /// measure (a legend with no kills recorded has none for kills).
  final int eligible;

  const MapLegendInsight({
    required this.mapName,
    required this.games,
    required this.totalRp,
    required this.best,
    this.worst,
    this.qualified = 0,
    this.eligible = 0,
  });

  double get avgRpPerGame => games == 0 ? 0 : totalRp / games;

  /// Whether the map's own record has enough games behind it to be shown.
  bool get hasRecord => games >= kMinGamesForInsight;
}

/// For each map in [cells], the player's record there and their best and worst
/// legend under [metric], most-played map first. See [rankByMetric] for how
/// ties and thin samples are handled.
List<MapLegendInsight> mapLegendInsights(
  List<LegendMapCell> cells, {
  BestMetric metric = kDefaultBestMetric,
}) {
  final byMap = <String, List<LegendMapCell>>{};
  for (final c in cells) {
    byMap.putIfAbsent(c.mapName, () => []).add(c);
  }

  final insights =
      [
        for (final e in byMap.entries)
          () {
            final ranked = rankByMetric(
              e.value,
              metric,
              nameOf: (c) => c.legend,
            );
            final (:best, :worst) = bestAndWorst(ranked, metric);
            return MapLegendInsight(
              mapName: e.key,
              games: e.value.fold(0, (a, c) => a + c.games),
              totalRp: e.value.fold(0, (a, c) => a + c.totalRp),
              best: best,
              worst: worst,
              qualified: ranked.length,
              eligible: e.value
                  .where((c) => c.games >= kMinGamesForInsight)
                  .length,
            );
          }(),
      ]..sort((a, b) {
        final g = b.games.compareTo(a.games);
        return g != 0 ? g : a.mapName.compareTo(b.mapName);
      });
  return insights;
}

// ── Session detection ───────────────────────────────────────────────────────

class RankedSession {
  final DateTime start; // first match start
  final DateTime end; // last match end
  final int games;
  final int netRp;
  final int totalKills;
  final int totalDamage;

  /// Games in this session that reported a kills / damage tracker. Any
  /// per-game average of [totalKills] / [totalDamage] must divide by these,
  /// not by [games]: upstream only reports the tracker a legend has equipped.
  final int killsGames;
  final int damageGames;

  /// Games that gained RP and games that lost it, so [wins] over
  /// [wins] + [losses] is the win rate; a game that moved nothing is neither.
  /// [totalLengthSecs] is the time the games themselves ran. All 0 when the
  /// session wasn't built from matches.
  final int wins;
  final int losses;
  final int totalLengthSecs;

  /// The matches in this session, newest first — drives the session drill-down.
  final List<RankedMatch> matches;

  const RankedSession({
    required this.start,
    required this.end,
    required this.games,
    required this.netRp,
    required this.totalKills,
    required this.totalDamage,
    required this.killsGames,
    required this.damageGames,
    this.wins = 0,
    this.losses = 0,
    this.totalLengthSecs = 0,
    required this.matches,
  });

  /// Wall-clock span of the session (first start → last end).
  Duration get duration => end.difference(start);

  /// The legend that did best this session under [metric], or null when none
  /// has a figure for it (no games, or no kills reported for a kills measure).
  /// A legend with [kMinGamesForInsight] games or more is preferred, so a
  /// single game doesn't crown one; failing that the rest are ranked.
  String? bestLegendBy(BestMetric metric) => rankByMetric(
    legendBreakdowns(matches),
    metric,
    nameOf: (l) => l.legend,
    softGate: true,
  ).firstOrNull?.legend;
}

/// The session each match of [newestFirst] belongs to, as a number that is 0
/// for the newest session. A new session starts wherever the gap between a
/// match's end and the start of the one after it is larger than [kSessionGap]. The one
/// definition of a session boundary, shared by [sessionize] and the History
/// tab.
List<int> sessionNumbers(List<RankedMatch> newestFirst) {
  final numbers = <int>[];
  var current = -1;
  for (var i = 0; i < newestFirst.length; i++) {
    if (i == 0 ||
        newestFirst[i - 1].startTime.difference(newestFirst[i].endTime) >
            kSessionGap) {
      current++;
    }
    numbers.add(current);
  }
  return numbers;
}

/// Groups ranked matches into sessions separated by gaps larger than [kSessionGap].
/// Returned newest session first. Assumes [ranked] is already ranked-only
/// filtered.
List<RankedSession> sessionize(List<RankedMatch> ranked) {
  final newestFirst = ranked.toList()
    ..sort((a, b) => b.startTime.compareTo(a.startTime));
  if (newestFirst.isEmpty) return [];

  final numbers = sessionNumbers(newestFirst);
  final sessions = <RankedSession>[];
  var bucket = <RankedMatch>[];

  void flush() {
    bucket = bucket.reversed.toList(); // chronological
    var rp = 0, kills = 0, damage = 0, killsGames = 0, damageGames = 0;
    var wins = 0, losses = 0, lengthSecs = 0;
    for (final m in bucket) {
      rp += m.effectiveRpChange;
      if (m.effectiveRpChange > 0) wins++;
      if (m.effectiveRpChange < 0) losses++;
      lengthSecs += m.lengthSecs;
      final k = m.kills, d = m.damage;
      if (k != null) {
        kills += k;
        killsGames++;
      }
      if (d != null) {
        damage += d;
        damageGames++;
      }
    }
    sessions.add(
      RankedSession(
        start: bucket.first.startTime,
        // bucket is sorted by *start* time, so the start-sorted last match
        // isn't necessarily the one that ends last — upstream reconstructs
        // timestamps from polling gaps, so an out-of-order end is reachable.
        end: bucket
            .map((m) => m.endTime)
            .reduce((a, b) => a.isAfter(b) ? a : b),
        games: bucket.length,
        netRp: rp,
        totalKills: kills,
        totalDamage: damage,
        killsGames: killsGames,
        damageGames: damageGames,
        wins: wins,
        losses: losses,
        totalLengthSecs: lengthSecs,
        // bucket is chronological; expose newest-first for the drill-down list.
        matches: bucket.reversed.toList(),
      ),
    );
  }

  for (var i = 0; i < newestFirst.length; i++) {
    if (i > 0 && numbers[i] != numbers[i - 1]) {
      flush();
      bucket = [];
    }
    bucket.add(newestFirst[i]);
  }
  flush();

  return sessions;
}

// ── Rank progress (promotion tracker + optional goal) ───────────────────────

/// Where the player sits on the rank ladder and how far the next division — and
/// an optional user-set goal — are at their current RP-per-game pace.
///
/// Pace uses the window's RP/game with reset games already left out, so
/// end-of-split placement drops don't poison the estimate.
/// Sentinel [goalIndex] meaning "Apex Predator" — not a real [kRankLadder]
/// index but stored the same way in SharedPreferences.
const int kPredatorGoalIndex = 99;

class RankProgress {
  final int currentRp;
  final int currentIndex; // index into kRankLadder
  final double avgRpPerGame;
  final int? goalIndex; // user goal ladder index; null = no goal set
  final int? predatorRp; // live cutoff from /predator, null if unavailable

  const RankProgress({
    required this.currentRp,
    required this.currentIndex,
    required this.avgRpPerGame,
    required this.goalIndex,
    this.predatorRp,
  });

  factory RankProgress.from(
    RankedSummary summary, {
    int? goalIndex,
    int? predatorRp,
  }) {
    final avg = summary.games == 0 ? 0.0 : summary.netRp / summary.games;
    return RankProgress(
      currentRp: summary.currentRp,
      currentIndex: rankIndex(summary.currentRp),
      avgRpPerGame: avg,
      goalIndex: goalIndex,
      predatorRp: predatorRp,
    );
  }

  /// True once [currentRp] has crossed the live Predator cutoff — the same
  /// rule as everywhere else (see [isApexPredatorRp]): Master or above, and a
  /// usable cutoff, which a 0 or missing value from `/predator` is not.
  bool get isPredator => isApexPredatorRp(currentRp, predatorRp);

  RankDivision get current => isPredator
      ? RankDivision(kApexPredatorRank, null, predatorRp!, kPredatorColor)
      : kRankLadder[currentIndex];

  /// The immediate next division. At Master, this is the live Predator cutoff
  /// (if known) rather than null, so the progress bar keeps climbing instead
  /// of stalling at "top of the ladder" before the player actually is one.
  /// Null once [isPredator] is true, or at Master with no cutoff available.
  RankDivision? get next {
    if (isPredator) return null;
    if (currentIndex + 1 < kRankLadder.length) {
      return kRankLadder[currentIndex + 1];
    }
    final rp = usablePredatorCutoff(predatorRp);
    if (rp != null) {
      return RankDivision(kApexPredatorRank, null, rp, kPredatorColor);
    }
    return null;
  }

  bool get isPredatorGoal => goalIndex == kPredatorGoalIndex;

  /// The user's goal division, or null when no goal is set / goal is already
  /// surpassed. Predator goals use the live cutoff RP.
  RankDivision? get goal {
    final i = goalIndex;
    if (i == null) return null;
    if (isPredatorGoal) {
      final rp = usablePredatorCutoff(predatorRp);
      if (rp == null) return null;
      return RankDivision(kApexPredatorRank, null, rp, kPredatorColor);
    }
    if (i <= currentIndex || i >= kRankLadder.length) return null;
    return kRankLadder[i];
  }

  /// Fill fraction (0..1) between the current division floor and the next.
  double get progressToNext {
    final n = next;
    if (n == null) return 1;
    final span = n.rp - current.rp;
    if (span <= 0) return 1;
    return ((currentRp - current.rp) / span).clamp(0.0, 1.0);
  }

  int rpTo(RankDivision div) => div.rp - currentRp;

  /// Games to reach [div] at the current pace. 0 if already there; null when the
  /// pace is flat/negative (no honest estimate).
  int? gamesTo(RankDivision div) {
    final rp = rpTo(div);
    if (rp <= 0) return 0;
    if (avgRpPerGame <= 0) return null;
    return (rp / avgRpPerGame).ceil();
  }
}

// ── Time-of-day performance ─────────────────────────────────────────────────

class HourBucket {
  final int hourLocal; // 0..23, device-local
  final int games;
  final int netRp;

  const HourBucket({
    required this.hourLocal,
    required this.games,
    required this.netRp,
  });

  double get avgRpPerGame => games == 0 ? 0 : netRp / games;
}

/// Buckets ranked matches by local hour-of-day (from each match's start time).
/// Only hours with at least one game are returned, ordered 0→23. Assumes
/// [matches] is already ranked-only filtered.
List<HourBucket> timeOfDayBuckets(List<RankedMatch> matches) =>
    _bucketByHour(matches.map((m) => (m.startTime, m.effectiveRpChange)));

/// Buckets ranked rows given only their raw UTC start-millis and RP change —
/// the counterpart to [timeOfDayBuckets] for the SQL projection, so the store
/// can build the Lifetime time-of-day chart without hydrating a full
/// [RankedMatch] per row. Callers must pass rows already scoped to matches that
/// count toward the stats (the store's `_rankedScope`).
List<HourBucket> timeOfDayBucketsFromRankedRows(
  Iterable<(int startMsUtc, int rpChange)> rows,
) => _bucketByHour(
  rows.map((r) {
    final (startMs, rp) = r;
    return (DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true), rp);
  }),
);

/// Shared core: tallies (UTC start time, effective RP) pairs into per-local-hour
/// buckets. Only hours with at least one game are returned, ordered 0→23.
List<HourBucket> _bucketByHour(Iterable<(DateTime, int)> entries) {
  final games = <int, int>{};
  final rp = <int, int>{};
  for (final (start, effectiveRp) in entries) {
    final hour = start.toLocal().hour;
    games[hour] = (games[hour] ?? 0) + 1;
    rp[hour] = (rp[hour] ?? 0) + effectiveRp;
  }
  final hours = games.keys.toList()..sort();
  return [
    for (final h in hours)
      HourBucket(hourLocal: h, games: games[h]!, netRp: rp[h]!),
  ];
}

// ── Day-of-week performance ──────────────────────────────────────────────────

class WeekdayBucket {
  final int weekday; // 1..7, device-local — DateTime.monday..DateTime.sunday
  final int games;
  final int netRp;

  const WeekdayBucket({
    required this.weekday,
    required this.games,
    required this.netRp,
  });

  double get avgRpPerGame => games == 0 ? 0 : netRp / games;
}

/// Buckets ranked matches by local day-of-week (from each match's start time).
/// Only days with at least one game are returned, ordered Monday→Sunday.
/// Assumes [matches] is already ranked-only filtered.
List<WeekdayBucket> dayOfWeekBuckets(List<RankedMatch> matches) =>
    _bucketByWeekday(matches.map((m) => (m.startTime, m.effectiveRpChange)));

/// Buckets ranked rows given only their raw UTC start-millis and RP change —
/// the counterpart to [dayOfWeekBuckets] for the SQL projection, so the store
/// can build the Lifetime day-of-week chart without hydrating a full
/// [RankedMatch] per row. Callers must pass rows already scoped to matches that
/// count toward the stats (the store's `_rankedScope`).
List<WeekdayBucket> dayOfWeekBucketsFromRankedRows(
  Iterable<(int startMsUtc, int rpChange)> rows,
) => _bucketByWeekday(
  rows.map((r) {
    final (startMs, rp) = r;
    return (DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true), rp);
  }),
);

/// Shared core: tallies (UTC start time, effective RP) pairs into per-local
/// weekday buckets. Only days with at least one game are returned, ordered
/// Monday→Sunday.
List<WeekdayBucket> _bucketByWeekday(Iterable<(DateTime, int)> entries) {
  final games = <int, int>{};
  final rp = <int, int>{};
  for (final (start, effectiveRp) in entries) {
    final weekday = start.toLocal().weekday;
    games[weekday] = (games[weekday] ?? 0) + 1;
    rp[weekday] = (rp[weekday] ?? 0) + effectiveRp;
  }
  final weekdays = games.keys.toList()..sort();
  return [
    for (final d in weekdays)
      WeekdayBucket(weekday: d, games: games[d]!, netRp: rp[d]!),
  ];
}

// ── Personal records & session trends ───────────────────────────────────────

/// The Lifetime-scope equivalent of [PersonalRecords]'s three best-game
/// fields — fed by [RankedHistoryStore.personalBestGamesFor]'s SQL
/// `ORDER BY ... LIMIT 1` queries instead of full match hydration. No
/// streak or trend fields: those need chronological match/session data that
/// Lifetime deliberately never loads.
typedef PersonalBestGames = ({
  RankedMatch? bestRpGame,
  RankedMatch? bestKillsGame,
  RankedMatch? bestDamageGame,
});

/// Standout single-game and streak stats for the Records & Compare screen.
/// Built from ranked matches only; null best-kills/best-damage mean no match
/// in range reported that tracker. [bestStreakStart] is the
/// first match of the best streak, null when that streak is 0.
class PersonalRecords {
  final RankedMatch? bestRpGame;
  final RankedMatch? bestKillsGame;
  final RankedMatch? bestDamageGame;
  final int currentWinStreak;
  final int bestWinStreak;
  final DateTime? bestStreakStart;

  /// The games of the best streak, oldest first: [bestWinStreak] of them.
  final List<RankedMatch> bestStreakMatches;

  const PersonalRecords({
    this.bestRpGame,
    this.bestKillsGame,
    this.bestDamageGame,
    required this.currentWinStreak,
    required this.bestWinStreak,
    this.bestStreakStart,
    this.bestStreakMatches = const [],
  });
}

/// Computes [PersonalRecords] from ranked matches (any order). A "win" is the
/// same effective-RP-gain > 0 definition used everywhere else in this file
/// (see [legendBreakdowns]'s wins/losses). Only a loss (effective RP < 0)
/// breaks a streak. Matches that don't count toward the stats (hand-excluded or
/// auto-excluded for an implausible RP swing) are skipped, so they leave the
/// streak exactly where it was.
///
/// A tie on a best-game stat goes to the most recently ended match — the same
/// `end_ms DESC` tie-break `RankedHistoryStore.personalBestGamesFor` uses, so
/// the split view and Lifetime name the same match for the same record.
PersonalRecords personalRecords(List<RankedMatch> all) {
  final matches = all.where((m) => m.countsTowardStats).toList();
  if (matches.isEmpty) {
    return const PersonalRecords(currentWinStreak: 0, bestWinStreak: 0);
  }

  // Whether [m] displaces [best] on [value]: higher wins, newer breaks a tie.
  bool beats(
    RankedMatch m,
    RankedMatch? best,
    int Function(RankedMatch) value,
  ) {
    if (best == null) return true;
    final a = value(m), b = value(best);
    return a > b || (a == b && m.endTime.isAfter(best.endTime));
  }

  RankedMatch? bestRp, bestKills, bestDamage;
  for (final m in matches) {
    if (beats(m, bestRp, (x) => x.rpChange)) bestRp = m;
    if (m.kills != null && beats(m, bestKills, (x) => x.kills!)) {
      bestKills = m;
    }
    if (m.damage != null && beats(m, bestDamage, (x) => x.damage!)) {
      bestDamage = m;
    }
  }

  final chrono = matches.toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  var current = 0, best = 0;
  DateTime? runStart, bestStart;
  var run = <RankedMatch>[];
  var bestRun = <RankedMatch>[];
  for (final m in chrono) {
    final rp = m.effectiveRpChange;
    if (rp > 0) {
      runStart ??= m.startTime;
      run.add(m);
      current += 1;
      if (current > best) {
        best = current;
        bestStart = runStart;
        bestRun = List.of(run);
      }
    } else if (rp < 0) {
      current = 0;
      runStart = null;
      run = [];
    }
  }

  return PersonalRecords(
    bestRpGame: bestRp,
    bestKillsGame: bestKills,
    bestDamageGame: bestDamage,
    currentWinStreak: current,
    bestWinStreak: best,
    bestStreakStart: bestStart,
    bestStreakMatches: bestRun,
  );
}

/// Avg-per-game comparison between the most recent [window] sessions and the
/// [window] before that, for whichever total [totalOf] extracts (net RP,
/// kills, damage, ...). Null below `window * 2` sessions — not enough data
/// for two windows, or when either window has no games ([gamesOf] sums to 0,
/// e.g. no session in it reported the tracker). [gamesOf] must count only the
/// games that contributed to [totalOf]. [sessions] must be newest-first,
/// matching [sessionize]'s output.
class SessionTrend {
  final double recent;
  final double previous;
  const SessionTrend({required this.recent, required this.previous});

  double get delta => recent - previous;
}

SessionTrend? sessionTrend(
  List<RankedSession> sessions, {
  required int Function(RankedSession) totalOf,
  required int Function(RankedSession) gamesOf,
  int window = 3,
}) {
  if (sessions.length < window * 2) return null;

  double? avgPerGame(Iterable<RankedSession> range) {
    final games = range.fold(0, (s, e) => s + gamesOf(e));
    final total = range.fold(0, (s, e) => s + totalOf(e));
    return games == 0 ? null : total / games;
  }

  final recent = avgPerGame(sessions.take(window));
  final previous = avgPerGame(sessions.skip(window).take(window));
  if (recent == null || previous == null) return null;
  return SessionTrend(recent: recent, previous: previous);
}

/// How an entity's recent games compare with its average: [recent] is the
/// average the newest games gave, [overall] the average over all of its games,
/// the figure its row and sheet already show. [delta] is how far recent play
/// sits above (or below) that average.
class TrendChange {
  final double recent;
  final double overall;
  const TrendChange({required this.recent, required this.overall});

  double get delta => recent - overall;
}

/// [recent] vs. [overall] average for whichever value [valueOf] extracts from
/// each match: [recent] is the average across the newest [window] games of
/// [newestFirst] (which must be in that order), [overall] the average across
/// all of them. Null when either has no match with a value at all, so a stat
/// that was never reported isn't shown as a change from 0. A null [valueOf]
/// (e.g. untracked kills/damage) excludes that match from both the total and
/// the game count, rather than counting it as a zero.
/// Windowed by game count, not sessions: games are the sample, and a session
/// of one legend can be a single game or twenty.
TrendChange? _trendChange(
  List<RankedMatch> newestFirst, {
  required int window,
  required int? Function(RankedMatch) valueOf,
}) {
  double? avgOf(Iterable<RankedMatch> range) {
    var total = 0, games = 0;
    for (final m in range) {
      final v = valueOf(m);
      if (v != null) {
        total += v;
        games++;
      }
    }
    return games == 0 ? null : total / games;
  }

  final recent = avgOf(newestFirst.take(window));
  final overall = avgOf(newestFirst);
  // No reading in a range is "no data", not an average of 0.
  if (recent == null || overall == null) return null;
  return TrendChange(recent: recent, overall: overall);
}

/// RP/kills/damage [TrendChange]s for one legend's or map's [matches]
/// (already filtered to that entity - see [canonicalLegendName]/
/// [canonicalMapKey]).
typedef EntityTrends = ({
  TrendChange? rp,
  TrendChange? kills,
  TrendChange? damage,
});

/// The trends of [matches], with the newest [recentGames] as the recent part.
/// Pick that count with `resolveEntityTrendWindow`. Null for each below twice
/// [recentGames] games - the recent games would be most of the history.
EntityTrends entityTrends(
  List<RankedMatch> matches, {
  required int recentGames,
}) {
  if (recentGames < 1 || matches.length < recentGames * 2) {
    return (rp: null, kills: null, damage: null);
  }
  // Sorted once, for all three.
  final newestFirst = matches.toList()
    ..sort((a, b) => b.startTime.compareTo(a.startTime));
  return (
    rp: _trendChange(
      newestFirst,
      window: recentGames,
      valueOf: (m) => m.effectiveRpChange,
    ),
    kills: _trendChange(
      newestFirst,
      window: recentGames,
      valueOf: (m) => m.kills,
    ),
    damage: _trendChange(
      newestFirst,
      window: recentGames,
      valueOf: (m) => m.damage,
    ),
  );
}
