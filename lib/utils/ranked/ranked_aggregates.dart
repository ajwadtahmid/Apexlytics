/// Pure aggregation functions over a list of [RankedMatch].
///
/// Everything here is deterministic and widget-free so it can be unit-tested in
/// isolation. The UI layer (Phase 2+) consumes these view models directly.
library;

import '../../constants/legend_constants.dart';
import '../../constants/rank_constants.dart';
import '../../constants/map_constants.dart';
import '../../models/ranked_match.dart';
import '../formatting/rank_utils.dart' show rankIndex;

/// Default gap that separates one play session from the next.
const Duration kSessionGap = Duration(hours: 2);

/// Minimum games before a legend/map qualifies for "best/worst" insights, so a
/// single lucky game doesn't crown a legend.
const int kMinGamesForInsight = 3;

/// Returns only ranked (Battle Royale) matches, newest first.
List<RankedMatch> rankedOnly(List<RankedMatch> all) {
  final list = all.where((m) => m.isRanked).toList()
    ..sort((a, b) => b.endTime.compareTo(a.endTime));
  return list;
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
  double get avgKills => killsGames == 0 ? 0 : totalKills / killsGames;
  double get avgDamage => damageGames == 0 ? 0 : totalDamage / damageGames;
  double get avgGameLengthSecs => games == 0 ? 0 : totalLengthSecs / games;

  /// Games with no kills/damage reported, for the "based on N games" note.
  int get killsGamesMissing => games - killsGames;
  int get damageGamesMissing => games - damageGames;

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
RankedSummary summarize(List<RankedMatch> matches) {
  if (matches.isEmpty) return RankedSummary.empty;

  // Find the newest match for currentRp/rankImg without a full sort.
  var newest = matches.first;
  var netRp = 0, kills = 0, damage = 0, length = 0, wins = 0, losses = 0;
  var killsGames = 0, damageGames = 0;
  for (final m in matches) {
    netRp += m.effectiveRpChange;
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
    if (m.effectiveRpChange > 0) {
      wins++;
    } else if (m.effectiveRpChange < 0) {
      losses++;
    }
    if (m.endTime.isAfter(newest.endTime)) newest = m;
  }
  return RankedSummary(
    games: matches.length,
    netRp: netRp,
    currentRp: newest.cumulativeRp,
    latestRankImg: newest.rankImg,
    totalKills: kills,
    totalDamage: damage,
    killsGames: killsGames,
    damageGames: damageGames,
    totalLengthSecs: length,
    wins: wins,
    losses: losses,
  );
}

// ── Legend breakdown ────────────────────────────────────────────────────────

class LegendBreakdown {
  final String legend;
  final int games;
  final int totalRp; // Σ rpChange on this legend
  final int totalKills;
  final int totalDamage;

  /// Games whose kills/damage upstream reported — the divisor for the averages.
  /// See [RankedSummary.killsGames].
  final int killsGames;
  final int damageGames;

  final int totalLengthSecs;
  final int wins;
  final int losses;

  const LegendBreakdown({
    required this.legend,
    required this.games,
    required this.totalRp,
    required this.totalKills,
    required this.totalDamage,
    required this.killsGames,
    required this.damageGames,
    required this.totalLengthSecs,
    required this.wins,
    required this.losses,
  });

  double get avgRpPerGame => games == 0 ? 0 : totalRp / games;
  double get avgKills => killsGames == 0 ? 0 : totalKills / killsGames;
  double get avgDamage => damageGames == 0 ? 0 : totalDamage / damageGames;
  double get avgLengthSecs => games == 0 ? 0 : totalLengthSecs / games;
  int get decidedGames => wins + losses;
  double get winRate => decidedGames == 0 ? 0 : wins / decidedGames;
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
  final out = byLegend.entries.map((e) {
    var rp = 0, kills = 0, damage = 0, length = 0, wins = 0, losses = 0;
    var killsGames = 0, damageGames = 0;
    for (final m in e.value) {
      rp += m.effectiveRpChange;
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
      if (m.effectiveRpChange > 0) {
        wins++;
      } else if (m.effectiveRpChange < 0) {
        losses++;
      }
    }
    return LegendBreakdown(
      legend: e.key,
      games: e.value.length,
      totalRp: rp,
      totalKills: kills,
      totalDamage: damage,
      killsGames: killsGames,
      damageGames: damageGames,
      totalLengthSecs: length,
      wins: wins,
      losses: losses,
    );
  }).toList()..sort((a, b) => b.totalRp.compareTo(a.totalRp));
  return out;
}

// ── Map breakdown ───────────────────────────────────────────────────────────

class MapBreakdown {
  final String mapKey;
  final String displayName;
  final int games;
  final int totalRp;
  final int totalKills;
  final int totalDamage;

  /// Games whose kills/damage upstream reported — the divisor for the averages.
  /// See [RankedSummary.killsGames].
  final int killsGames;
  final int damageGames;

  final int totalLengthSecs;
  final int wins;
  final int losses;

  const MapBreakdown({
    required this.mapKey,
    required this.displayName,
    required this.games,
    required this.totalRp,
    required this.totalKills,
    required this.totalDamage,
    required this.killsGames,
    required this.damageGames,
    required this.totalLengthSecs,
    required this.wins,
    required this.losses,
  });

  double get avgRpPerGame => games == 0 ? 0 : totalRp / games;
  double get avgKills => killsGames == 0 ? 0 : totalKills / killsGames;
  double get avgDamage => damageGames == 0 ? 0 : totalDamage / damageGames;
  double get avgLengthSecs => games == 0 ? 0 : totalLengthSecs / games;
  int get decidedGames => wins + losses;
  double get winRate => decidedGames == 0 ? 0 : wins / decidedGames;
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
  final out = byMap.entries.map((e) {
    var rp = 0, kills = 0, damage = 0, length = 0, wins = 0, losses = 0;
    var killsGames = 0, damageGames = 0;
    for (final m in e.value) {
      rp += m.effectiveRpChange;
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
      if (m.effectiveRpChange > 0) {
        wins++;
      } else if (m.effectiveRpChange < 0) {
        losses++;
      }
    }
    final rawKey = representativeKey[e.key]!;
    return MapBreakdown(
      mapKey: rawKey,
      displayName: battleRoyaleMapName(rawKey),
      games: e.value.length,
      totalRp: rp,
      totalKills: kills,
      totalDamage: damage,
      killsGames: killsGames,
      damageGames: damageGames,
      totalLengthSecs: length,
      wins: wins,
      losses: losses,
    );
  }).toList()..sort((a, b) => b.games.compareTo(a.games));
  return out;
}

// ── Legend × Map matrix ──────────────────────────────────────────────────────
//
// A standalone drill-down, self-contained on purpose: it touches no other
// aggregate here and nothing else calls it, so it stays a one-function,
// one-widget feature.

class LegendMapCell {
  final String legend;
  final String mapName;
  final int games;
  final int totalRp;
  final int wins;
  final int losses;

  const LegendMapCell({
    required this.legend,
    required this.mapName,
    required this.games,
    required this.totalRp,
    required this.wins,
    required this.losses,
  });

  double get avgRpPerGame => games == 0 ? 0 : totalRp / games;
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
    final legend = kLegendsByName[m.legend.toLowerCase()]?.name;
    final mapName = battleRoyaleMapInfo(m.mapKey)?.name;
    if (legend == null || mapName == null) continue;
    byPair.putIfAbsent((legend, mapName), () => []).add(m);
  }

  return [
    for (final entry in byPair.entries)
      LegendMapCell(
        legend: entry.key.$1,
        mapName: entry.key.$2,
        games: entry.value.length,
        totalRp: entry.value.fold(0, (sum, m) => sum + m.effectiveRpChange),
        wins: entry.value.where((m) => m.effectiveRpChange > 0).length,
        losses: entry.value.where((m) => m.effectiveRpChange < 0).length,
      ),
  ];
}

// ── Session detection ───────────────────────────────────────────────────────

class RankedSession {
  final DateTime start; // first match start
  final DateTime end; // last match end
  final int games;
  final int netRp;
  final int totalKills;
  final int totalDamage;

  /// The matches in this session, newest first — drives the session drill-down.
  final List<RankedMatch> matches;

  const RankedSession({
    required this.start,
    required this.end,
    required this.games,
    required this.netRp,
    required this.totalKills,
    required this.totalDamage,
    required this.matches,
  });

  /// Wall-clock span of the session (first start → last end).
  Duration get duration => end.difference(start);

  /// Legend with the highest effective RP this session, or null when empty.
  /// Ties break toward the legend with more games, then alphabetically.
  String? get bestLegend {
    if (matches.isEmpty) return null;
    final rp = <String, int>{};
    final count = <String, int>{};
    for (final m in matches) {
      rp[m.legend] = (rp[m.legend] ?? 0) + m.effectiveRpChange;
      count[m.legend] = (count[m.legend] ?? 0) + 1;
    }
    final keys = rp.keys.toList()
      ..sort((a, b) {
        final byRp = rp[b]!.compareTo(rp[a]!);
        if (byRp != 0) return byRp;
        final byGames = count[b]!.compareTo(count[a]!);
        return byGames != 0 ? byGames : a.compareTo(b);
      });
    return keys.first;
  }
}

/// Groups ranked matches into sessions separated by gaps larger than [gap].
/// Returned newest session first. Assumes [ranked] is already ranked-only
/// filtered.
List<RankedSession> sessionize(
  List<RankedMatch> ranked, {
  Duration gap = kSessionGap,
}) {
  final chrono = ranked.toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  if (chrono.isEmpty) return [];

  final sessions = <RankedSession>[];
  var bucket = <RankedMatch>[chrono.first];

  void flush() {
    var rp = 0, kills = 0, damage = 0;
    for (final m in bucket) {
      rp += m.effectiveRpChange;
      // Session totals are sums, not averages, so an unreported match simply
      // contributes nothing rather than needing its own coverage count.
      kills += m.kills ?? 0;
      damage += m.damage ?? 0;
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
        // bucket is chronological; expose newest-first for the drill-down list.
        matches: bucket.reversed.toList(),
      ),
    );
  }

  for (var i = 1; i < chrono.length; i++) {
    final prev = chrono[i - 1];
    final cur = chrono[i];
    if (cur.startTime.difference(prev.endTime) > gap) {
      flush();
      bucket = [cur];
    } else {
      bucket.add(cur);
    }
  }
  flush();

  return sessions.reversed.toList();
}

// ── Rank progress (promotion tracker + optional goal) ───────────────────────

/// Where the player sits on the rank ladder and how far the next division — and
/// an optional user-set goal — are at their current RP-per-game pace.
///
/// Pace uses the window's effective RP/game (reset outliers already neutralized),
/// so end-of-split placement drops don't poison the estimate.
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

  /// True once [currentRp] has crossed the live Predator cutoff — mirrors the
  /// My Stats tab's `isPred` check, which reads straight off the RP value
  /// rather than assuming Master is the ceiling.
  bool get isPredator =>
      predatorRp != null && predatorRp! > 0 && currentRp >= predatorRp!;

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
    final rp = predatorRp;
    if (rp != null && rp > 0) {
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
      final rp = predatorRp;
      if (rp == null || rp <= 0) return null;
      return RankDivision(kApexPredatorRank, null, rp, kPredatorColor);
    }
    if (i <= currentIndex || i >= kRankLadder.length) return null;
    return kRankLadder[i];
  }

  bool get atTop => next == null;

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
/// [RankedMatch] per row. Callers must pass already-ranked rows; RP-reset
/// outliers are neutralized here to match [RankedMatch.effectiveRpChange].
List<HourBucket> timeOfDayBucketsFromRankedRows(
  Iterable<(int startMsUtc, int rpChange)> rows,
) => _bucketByHour(
  rows.map((r) {
    final (startMs, rp) = r;
    final effectiveRp = effectiveRpOf(rp);
    return (
      DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
      effectiveRp,
    );
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
/// [RankedMatch] per row. Callers must pass already-ranked rows; RP-reset
/// outliers are neutralized here to match [RankedMatch.effectiveRpChange].
List<WeekdayBucket> dayOfWeekBucketsFromRankedRows(
  Iterable<(int startMsUtc, int rpChange)> rows,
) => _bucketByWeekday(
  rows.map((r) {
    final (startMs, rp) = r;
    final effectiveRp = effectiveRpOf(rp);
    return (
      DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
      effectiveRp,
    );
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

/// Standout single-game and streak stats for the Personal Records screen.
/// Built from ranked matches only; null best-kills/best-damage mean no match
/// in range reported that tracker. [currentStreakStart]/[bestStreakStart] are
/// each streak's first match, null when that streak is 0.
class PersonalRecords {
  final RankedMatch? bestRpGame;
  final RankedMatch? bestKillsGame;
  final RankedMatch? bestDamageGame;
  final int currentWinStreak;
  final DateTime? currentStreakStart;
  final int bestWinStreak;
  final DateTime? bestStreakStart;

  const PersonalRecords({
    this.bestRpGame,
    this.bestKillsGame,
    this.bestDamageGame,
    required this.currentWinStreak,
    this.currentStreakStart,
    required this.bestWinStreak,
    this.bestStreakStart,
  });
}

/// Computes [PersonalRecords] from ranked matches (any order). A "win" is the
/// same effective-RP-gain > 0 definition used everywhere else in this file
/// (see [legendBreakdowns]'s wins/losses). Only a loss (effective RP < 0)
/// breaks a streak — an RP-neutral game (0, e.g. a reset outlier) is neither
/// a win nor a loss, so it leaves the streak exactly where it was.
PersonalRecords personalRecords(List<RankedMatch> matches) {
  if (matches.isEmpty) {
    return const PersonalRecords(currentWinStreak: 0, bestWinStreak: 0);
  }

  RankedMatch? bestRp, bestKills, bestDamage;
  for (final m in matches) {
    if (bestRp == null || m.effectiveRpChange > bestRp.effectiveRpChange) {
      bestRp = m;
    }
    if (m.kills != null && (bestKills == null || m.kills! > bestKills.kills!)) {
      bestKills = m;
    }
    if (m.damage != null &&
        (bestDamage == null || m.damage! > bestDamage.damage!)) {
      bestDamage = m;
    }
  }

  final chrono = matches.toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  var current = 0, best = 0;
  DateTime? runStart, bestStart;
  for (final m in chrono) {
    final rp = m.effectiveRpChange;
    if (rp > 0) {
      runStart ??= m.startTime;
      current += 1;
      if (current > best) {
        best = current;
        bestStart = runStart;
      }
    } else if (rp < 0) {
      current = 0;
      runStart = null;
    }
    // rp == 0: neutral game, streak (and its start) unchanged.
  }

  return PersonalRecords(
    bestRpGame: bestRp,
    bestKillsGame: bestKills,
    bestDamageGame: bestDamage,
    currentWinStreak: current,
    currentStreakStart: current > 0 ? runStart : null,
    bestWinStreak: best,
    bestStreakStart: bestStart,
  );
}

/// Avg-per-game comparison between the most recent [window] sessions and the
/// [window] before that, for whichever total [totalOf] extracts (net RP,
/// kills, damage, ...). Null below `window * 2` sessions — not enough data
/// for two windows. [sessions] must be newest-first, matching [sessionize]'s
/// output.
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

  double avgPerGame(Iterable<RankedSession> range) {
    final games = range.fold(0, (s, e) => s + gamesOf(e));
    final total = range.fold(0, (s, e) => s + totalOf(e));
    return games == 0 ? 0 : total / games;
  }

  return SessionTrend(
    recent: avgPerGame(sessions.take(window)),
    previous: avgPerGame(sessions.skip(window).take(window)),
  );
}

/// Recent-games window [entityTrends] compares against the rest of an
/// entity's history.
const int kTrendRecentGames = 10;

/// [current] is the entity's overall average (matches e.g.
/// [LegendBreakdown.avgRpPerGame]); [older] is what it was before that, so a
/// trend line reads as "your average used to be X, it's now the Y you see
/// above" rather than citing a third, unrelated figure.
class TrendChange {
  final double older;
  final double current;
  const TrendChange({required this.older, required this.current});

  double get delta => current - older;
}

/// [older] vs. [current] average for whichever value [valueOf] extracts from
/// each match. [current] is the average across all of [matches]; [older] is
/// the average across everything before the most recent [window] games.
/// Null below `window * 2` games - not enough history for "older" to mean
/// anything. A null [valueOf] (e.g. untracked kills/damage) excludes that
/// match from both the total and the game count, rather than as a zero.
/// Windowed by game count, not sessions, so a legend/map played in just a
/// couple of long sessions still gets a meaningful "recent" slice.
TrendChange? _trendChange(
  List<RankedMatch> matches, {
  required int? Function(RankedMatch) valueOf,
  int window = kTrendRecentGames,
}) {
  if (matches.length < window * 2) return null;

  final chrono = matches.toList()
    ..sort((a, b) => b.startTime.compareTo(a.startTime)); // newest first

  double avgOf(Iterable<RankedMatch> range) {
    var total = 0, games = 0;
    for (final m in range) {
      final v = valueOf(m);
      if (v != null) {
        total += v;
        games++;
      }
    }
    return games == 0 ? 0 : total / games;
  }

  return TrendChange(older: avgOf(chrono.skip(window)), current: avgOf(chrono));
}

/// RP/kills/damage [TrendChange]s for one legend's or map's [matches]
/// (already filtered to that entity - see [canonicalLegendName]/
/// [canonicalMapKey]).
typedef EntityTrends = ({
  TrendChange? rp,
  TrendChange? kills,
  TrendChange? damage,
});

EntityTrends entityTrends(List<RankedMatch> matches) => (
  rp: _trendChange(matches, valueOf: (m) => m.effectiveRpChange),
  kills: _trendChange(matches, valueOf: (m) => m.kills),
  damage: _trendChange(matches, valueOf: (m) => m.damage),
);
