/// Pure aggregation functions over a list of [RankedMatch].
///
/// Everything here is deterministic and widget-free so it can be unit-tested in
/// isolation. The UI layer (Phase 2+) consumes these view models directly.
library;

import '../../constants/ranked_map_constants.dart';
import '../../models/ranked_match.dart';

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

RankedSummary summarize(List<RankedMatch> all) {
  if (all.isEmpty) return RankedSummary.empty;
  final matches = all.where((m) => m.isRanked).toList();
  if (matches.isEmpty) return RankedSummary.empty;

  // Find the newest match for currentRp/rankImg without a full sort.
  var newest = matches.first;
  var netRp = 0, kills = 0, damage = 0, length = 0;
  for (final m in matches) {
    netRp += m.rpChange;
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
List<LegendBreakdown> legendBreakdowns(List<RankedMatch> all) {
  final byLegend = <String, List<RankedMatch>>{};
  for (final m in all.where((m) => m.isRanked)) {
    byLegend.putIfAbsent(m.legend, () => []).add(m);
  }
  final out = byLegend.entries.map((e) {
    var rp = 0, kills = 0, damage = 0, length = 0;
    for (final m in e.value) {
      rp += m.rpChange;
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
List<MapBreakdown> mapBreakdowns(List<RankedMatch> all) {
  final byMap = <String, List<RankedMatch>>{};
  for (final m in all.where((m) => m.isRanked)) {
    byMap.putIfAbsent(m.mapKey, () => []).add(m);
  }
  final out = byMap.entries.map((e) {
    var rp = 0, kills = 0, damage = 0;
    for (final m in e.value) {
      rp += m.rpChange;
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

  const RankedSession({
    required this.start,
    required this.end,
    required this.games,
    required this.netRp,
    required this.totalKills,
    required this.totalDamage,
  });
}

/// Groups ranked matches into sessions separated by gaps larger than [gap].
/// Returned newest session first.
List<RankedSession> sessionize(
  List<RankedMatch> ranked, {
  Duration gap = kSessionGap,
}) {
  final chrono = ranked.where((m) => m.isRanked).toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  if (chrono.isEmpty) return [];

  final sessions = <RankedSession>[];
  var bucket = <RankedMatch>[chrono.first];

  void flush() {
    var rp = 0, kills = 0, damage = 0;
    for (final m in bucket) {
      rp += m.rpChange;
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
List<TrackerAggregate> aggregateTrackers(
  List<RankedMatch> all, {
  double minCoverage = 0.8,
}) {
  final matches = all.where((m) => m.isRanked).toList();
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
List<RankedInsight> generateInsights(List<RankedMatch> all) {
  final matches = all.where((m) => m.isRanked).toList();
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
/// Only hours with at least one game are returned, ordered 0→23.
List<HourBucket> timeOfDayBuckets(List<RankedMatch> all) {
  final games = <int, int>{};
  final rp = <int, int>{};
  for (final m in all.where((m) => m.isRanked)) {
    final hour = m.startTime.toLocal().hour;
    games[hour] = (games[hour] ?? 0) + 1;
    rp[hour] = (rp[hour] ?? 0) + m.rpChange;
  }
  final hours = games.keys.toList()..sort();
  return [
    for (final h in hours)
      HourBucket(hourLocal: h, games: games[h]!, netRp: rp[h]!),
  ];
}
