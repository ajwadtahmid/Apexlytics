/// Pure aggregation functions over a list of [RankedMatch].
///
/// Everything here is deterministic and widget-free so it can be unit-tested in
/// isolation. The UI layer (Phase 2+) consumes these view models directly.
library;

import '../../constants/rank_constants.dart';
import '../../constants/ranked_map_constants.dart';
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
  final int totalLengthSecs;

  const RankedSummary({
    required this.games,
    required this.netRp,
    required this.currentRp,
    required this.latestRankImg,
    required this.totalKills,
    required this.totalDamage,
    required this.totalLengthSecs,
  });

  double get avgRpPerGame => games == 0 ? 0 : netRp / games;
  double get avgKills => games == 0 ? 0 : totalKills / games;
  double get avgDamage => games == 0 ? 0 : totalDamage / games;
  double get avgGameLengthSecs => games == 0 ? 0 : totalLengthSecs / games;

  static const empty = RankedSummary(
    games: 0,
    netRp: 0,
    currentRp: 0,
    latestRankImg: '',
    totalKills: 0,
    totalDamage: 0,
    totalLengthSecs: 0,
  );
}

/// Assumes [matches] is already ranked-only filtered (the caller owns that via
/// [rankedOnly]/`matchesInSplit`) — re-filtering on every call was pure waste.
RankedSummary summarize(List<RankedMatch> matches) {
  if (matches.isEmpty) return RankedSummary.empty;

  // Find the newest match for currentRp/rankImg without a full sort.
  var newest = matches.first;
  var netRp = 0, kills = 0, damage = 0, length = 0;
  for (final m in matches) {
    netRp += m.effectiveRpChange;
    kills += m.kills;
    damage += m.damage;
    length += m.lengthSecs;
    if (m.endTime.isAfter(newest.endTime)) newest = m;
  }
  return RankedSummary(
    games: matches.length,
    netRp: netRp,
    currentRp: newest.cumulativeRp,
    latestRankImg: newest.rankImg,
    totalKills: kills,
    totalDamage: damage,
    totalLengthSecs: length,
  );
}

// ── Legend breakdown ────────────────────────────────────────────────────────

class LegendBreakdown {
  final String legend;
  final int games;
  final int totalRp; // Σ rpChange on this legend
  final int totalKills;
  final int totalDamage;
  final int totalLengthSecs;

  const LegendBreakdown({
    required this.legend,
    required this.games,
    required this.totalRp,
    required this.totalKills,
    required this.totalDamage,
    required this.totalLengthSecs,
  });

  double get avgRpPerGame => games == 0 ? 0 : totalRp / games;
  double get avgKills => games == 0 ? 0 : totalKills / games;
  double get avgDamage => games == 0 ? 0 : totalDamage / games;
  double get avgLengthSecs => games == 0 ? 0 : totalLengthSecs / games;
}

/// Per-legend breakdown, sorted by total RP contribution (descending).
/// Assumes [matches] is already ranked-only filtered.
List<LegendBreakdown> legendBreakdowns(List<RankedMatch> matches) {
  final byLegend = <String, List<RankedMatch>>{};
  for (final m in matches) {
    byLegend.putIfAbsent(m.legend, () => []).add(m);
  }
  final out = byLegend.entries.map((e) {
    var rp = 0, kills = 0, damage = 0, length = 0;
    for (final m in e.value) {
      rp += m.effectiveRpChange;
      kills += m.kills;
      damage += m.damage;
      length += m.lengthSecs;
    }
    return LegendBreakdown(
      legend: e.key,
      games: e.value.length,
      totalRp: rp,
      totalKills: kills,
      totalDamage: damage,
      totalLengthSecs: length,
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

  const MapBreakdown({
    required this.mapKey,
    required this.displayName,
    required this.games,
    required this.totalRp,
    required this.totalKills,
    required this.totalDamage,
  });

  double get avgRpPerGame => games == 0 ? 0 : totalRp / games;
  double get avgKills => games == 0 ? 0 : totalKills / games;
  double get avgDamage => games == 0 ? 0 : totalDamage / games;
}

/// Per-map breakdown, sorted by games played (descending).
/// Assumes [matches] is already ranked-only filtered.
List<MapBreakdown> mapBreakdowns(List<RankedMatch> matches) {
  final byMap = <String, List<RankedMatch>>{};
  for (final m in matches) {
    byMap.putIfAbsent(m.mapKey, () => []).add(m);
  }
  final out = byMap.entries.map((e) {
    var rp = 0, kills = 0, damage = 0;
    for (final m in e.value) {
      rp += m.effectiveRpChange;
      kills += m.kills;
      damage += m.damage;
    }
    return MapBreakdown(
      mapKey: e.key,
      displayName: rankedMapName(e.key),
      games: e.value.length,
      totalRp: rp,
      totalKills: kills,
      totalDamage: damage,
    );
  }).toList()..sort((a, b) => b.games.compareTo(a.games));
  return out;
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
      kills += m.kills;
      damage += m.damage;
    }
    sessions.add(RankedSession(
      start: bucket.first.startTime,
      end: bucket.last.endTime,
      games: bucket.length,
      netRp: rp,
      totalKills: kills,
      totalDamage: damage,
      // bucket is chronological; expose newest-first for the drill-down list.
      matches: bucket.reversed.toList(),
    ));
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

  RankDivision get current => kRankLadder[currentIndex];

  /// The immediate next division, or null at the top of the ladder (Master —
  /// Apex Predator is a live ladder cutoff with no fixed RP threshold).
  RankDivision? get next =>
      currentIndex + 1 < kRankLadder.length ? kRankLadder[currentIndex + 1] : null;

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

// ── Tracker coverage / aggregation (the dynamic stat row) ───────────────────

class TrackerAggregate {
  final String name;
  final int matchesPresent;
  final int totalMatches;
  final num total;

  const TrackerAggregate({
    required this.name,
    required this.matchesPresent,
    required this.totalMatches,
    required this.total,
  });

  /// Fraction of matches in the window that carried this tracker (0..1).
  double get coverage => totalMatches == 0 ? 0 : matchesPresent / totalMatches;
  double get avgPerGame => matchesPresent == 0 ? 0 : total / matchesPresent;
}

/// Aggregates trackers that appear in at least [minCoverage] of the window's
/// ranked matches, so the stat row reflects *whatever the player actually runs*
/// rather than a hardcoded set. Sorted by coverage (desc), then total (desc).
/// Assumes [matches] is already ranked-only filtered.
List<TrackerAggregate> aggregateTrackers(
  List<RankedMatch> matches, {
  double minCoverage = 0.8,
}) {
  if (matches.isEmpty) return [];

  final present = <String, int>{};
  final totals = <String, num>{};
  for (final m in matches) {
    final seen = <String>{};
    for (final t in m.trackers) {
      if (seen.add(t.name)) {
        present[t.name] = (present[t.name] ?? 0) + 1;
        totals[t.name] = (totals[t.name] ?? 0) + t.value;
      }
    }
  }

  final out = totals.keys
      .map((name) => TrackerAggregate(
            name: name,
            matchesPresent: present[name] ?? 0,
            totalMatches: matches.length,
            total: totals[name] ?? 0,
          ))
      .where((t) => t.coverage >= minCoverage)
      .toList()
    ..sort((a, b) {
      final byCoverage = b.coverage.compareTo(a.coverage);
      return byCoverage != 0 ? byCoverage : b.total.compareTo(a.total);
    });
  return out;
}

// ── Auto-insights (strengths & weaknesses) ──────────────────────────────────

enum InsightTone { positive, negative, neutral }

class RankedInsight {
  final String label; // short headline, e.g. "Best legend"
  final String detail; // e.g. "Axle · +38 RP/game over 59 games"
  final InsightTone tone;

  const RankedInsight({
    required this.label,
    required this.detail,
    required this.tone,
  });
}

/// Derives a small set of the most useful strengths/weaknesses for the window.
/// Assumes [matches] is already ranked-only filtered.
List<RankedInsight> generateInsights(List<RankedMatch> matches) {
  if (matches.isEmpty) return [];

  final insights = <RankedInsight>[];
  final summary = summarize(matches);

  // Net RP headline.
  insights.add(RankedInsight(
    label: summary.netRp >= 0 ? 'Net gain' : 'Net loss',
    detail:
        '${summary.netRp >= 0 ? '+' : ''}${summary.netRp} RP over ${summary.games} games',
    tone: summary.netRp >= 0 ? InsightTone.positive : InsightTone.negative,
  ));

  // Best / worst legend (min games guard).
  final legends =
      legendBreakdowns(matches).where((l) => l.games >= kMinGamesForInsight).toList();
  if (legends.isNotEmpty) {
    final best = legends.reduce((a, b) => a.avgRpPerGame >= b.avgRpPerGame ? a : b);
    insights.add(RankedInsight(
      label: 'Best legend',
      detail:
          '${best.legend} · ${_signed(best.avgRpPerGame)} RP/game over ${best.games} games',
      tone: best.avgRpPerGame >= 0 ? InsightTone.positive : InsightTone.neutral,
    ));
    if (legends.length > 1) {
      final worst =
          legends.reduce((a, b) => a.avgRpPerGame <= b.avgRpPerGame ? a : b);
      if (worst.legend != best.legend) {
        insights.add(RankedInsight(
          label: 'Weakest legend',
          detail:
              '${worst.legend} · ${_signed(worst.avgRpPerGame)} RP/game over ${worst.games} games',
          tone: worst.avgRpPerGame >= 0 ? InsightTone.neutral : InsightTone.negative,
        ));
      }
    }
  }

  // Strongest map.
  final maps =
      mapBreakdowns(matches).where((m) => m.games >= kMinGamesForInsight).toList();
  if (maps.isNotEmpty) {
    final best = maps.reduce((a, b) => a.avgRpPerGame >= b.avgRpPerGame ? a : b);
    insights.add(RankedInsight(
      label: 'Strongest map',
      detail:
          '${best.displayName} · ${_signed(best.avgRpPerGame)} RP/game over ${best.games} games',
      tone: best.avgRpPerGame >= 0 ? InsightTone.positive : InsightTone.neutral,
    ));
  }

  return insights;
}

String _signed(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';

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
List<HourBucket> timeOfDayBuckets(List<RankedMatch> matches) {
  final games = <int, int>{};
  final rp = <int, int>{};
  for (final m in matches) {
    final hour = m.startTime.toLocal().hour;
    games[hour] = (games[hour] ?? 0) + 1;
    rp[hour] = (rp[hour] ?? 0) + m.effectiveRpChange;
  }
  final hours = games.keys.toList()..sort();
  return [
    for (final h in hours)
      HourBucket(hourLocal: h, games: games[h]!, netRp: rp[h]!),
  ];
}
