import 'package:flutter/foundation.dart' show kDebugMode, listEquals;

import '../utils/app_logger.dart';
import '../utils/formatting/json_utils.dart';
import 'season_meta.dart';

class PlayerStats {
  final String name;
  final String uid;
  final int level;
  final String rank;
  final int rankScore;
  final String platform;
  final String currentLegend;
  final bool isOnline;
  final bool isInGame;
  final List<EquippedTracker> trackers;
  final List<LegendStat> legendStats;
  final SeasonMeta? rankedSeason;

  PlayerStats({
    required this.name,
    required this.uid,
    required this.level,
    required this.rank,
    required this.rankScore,
    required this.platform,
    required this.currentLegend,
    required this.isOnline,
    required this.isInGame,
    required this.trackers,
    this.legendStats = const [],
    this.rankedSeason,
  });

  String get presence =>
      isInGame ? 'In Game' : (isOnline ? 'Online' : 'Offline');

  static int _parseInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    return false;
  }

  factory PlayerStats.fromJson(Map<String, dynamic> json) {
    final global = asObject(json['global']) ?? {};
    final legendsBlock = asObject(json['legends']) ?? {};
    final selected = asObject(legendsBlock['selected']) ?? {};
    final realtime = asObject(json['realtime']) ?? {};
    final rankMap = asObject(global['rank']);

    return PlayerStats(
      name: asString(global['name']) ?? 'Unknown',
      uid: global['uid']?.toString() ?? '',
      level: _parseInt(global['level']),
      rank: asString(rankMap?['rankName']) ?? 'Unranked',
      rankScore: _parseInt(rankMap?['rankScore']),
      platform: asString(global['platform']) ?? 'Unknown',
      // API returns 'LegendName' in PascalCase — not a typo.
      currentLegend: asString(selected['LegendName']) ?? 'Unknown',
      isOnline: _parseBool(realtime['isOnline']),
      isInGame: _parseBool(realtime['isInGame']),
      trackers: _parseTrackers(asList(selected['data']) ?? []),
      legendStats: _parseLegendStats(
        asObject(legendsBlock['all']) ?? {},
      ),
      rankedSeason: _parseRankedSeason(rankMap),
    );
  }

  static List<EquippedTracker> _parseTrackers(List selectedData) {
    final trackers = <EquippedTracker>[];
    for (final stat in selectedData) {
      if (stat is! Map) {
        final msg = 'Unexpected tracker format: ${stat.runtimeType}';
        if (kDebugMode) throw FormatException(msg);
        log.w(msg);
        continue;
      }
      trackers.add(
        EquippedTracker(
          name: stat['name'] as String? ?? '',
          value: _parseInt(stat['value']),
        ),
      );
    }
    return trackers;
  }

  static List<LegendStat> _parseLegendStats(Map<String, dynamic> allLegends) {
    final legendStats = <LegendStat>[];
    allLegends.forEach((legendName, legendData) {
      if (legendData is! Map) return;
      final data = asList(asObject(legendData)?['data']) ?? [];
      final trackers = <LegendTracker>[];
      for (final stat in data) {
        if (stat is! Map) continue;
        final key = asString(stat['key']) ?? '';
        if (key.isEmpty) continue;
        trackers.add(
          LegendTracker(
            key: key,
            displayName: asString(stat['name']) ?? key,
            value: _parseInt(stat['value']),
          ),
        );
      }
      if (trackers.isNotEmpty) {
        legendStats.add(LegendStat(name: legendName, trackers: trackers));
      }
    });
    return legendStats;
  }

  static SeasonMeta? _parseRankedSeason(Map<String, dynamic>? rankMap) {
    final seasonId = asString(rankMap?['rankedSeason']);
    final seasonMetaRaw = asObject(rankMap?['rankedSeasonMeta']);
    if (seasonId == null || seasonMetaRaw == null) return null;
    final startTs = seasonMetaRaw['start'];
    final endTs = seasonMetaRaw['end'];
    if (startTs is! num || endTs is! num) return null;
    return SeasonMeta.fromApi(
      id: seasonId,
      startSeconds: startTs.toInt(),
      endSeconds: endTs.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerStats &&
          uid == other.uid &&
          platform == other.platform &&
          name == other.name &&
          level == other.level &&
          rank == other.rank &&
          rankScore == other.rankScore &&
          currentLegend == other.currentLegend &&
          isOnline == other.isOnline &&
          isInGame == other.isInGame &&
          rankedSeason == other.rankedSeason &&
          listEquals(trackers, other.trackers) &&
          listEquals(legendStats, other.legendStats);

  @override
  int get hashCode => Object.hash(
    uid,
    platform,
    name,
    level,
    rank,
    rankScore,
    currentLegend,
    isOnline,
    isInGame,
    rankedSeason,
    Object.hashAll(trackers),
    Object.hashAll(legendStats),
  );
}

class EquippedTracker {
  final String name;
  final int value;

  const EquippedTracker({required this.name, required this.value});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EquippedTracker && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

// ── Per-legend tracker (one stat, e.g. "BR Kills: 6743") ─────────────────────

class LegendTracker {
  final String key;
  final String displayName;
  final int value;

  const LegendTracker({
    required this.key,
    required this.displayName,
    required this.value,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegendTracker &&
          other.key == key &&
          other.displayName == displayName &&
          other.value == value;

  @override
  int get hashCode => Object.hash(key, displayName, value);

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': displayName,
    'value': value,
  };

  factory LegendTracker.fromJson(Map<String, dynamic> json) => LegendTracker(
    key: json['key'] as String? ?? '',
    displayName: json['name'] as String? ?? json['key'] as String? ?? '',
    value: (json['value'] as num?)?.toInt() ?? 0,
  );
}

// ── Aggregated stats for one legend ──────────────────────────────────────────

class LegendStat {
  final String name;
  final List<LegendTracker> trackers;
  final DateTime? lastUpdated;

  const LegendStat({
    required this.name,
    required this.trackers,
    this.lastUpdated,
  });

  int get killCount {
    for (final t in trackers) {
      if (t.key == 'kills' || t.key == 'career_kills') return t.value;
    }
    return 0;
  }

  int get damageDealt {
    for (final t in trackers) {
      if (t.key == 'damage') return t.value;
    }
    return 0;
  }

  int get winsCount {
    for (final t in trackers) {
      if (t.key == 'wins' || t.key == 'career_wins') return t.value;
    }
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegendStat &&
          other.name == name &&
          other.lastUpdated == lastUpdated &&
          listEquals(other.trackers, trackers);

  @override
  int get hashCode => Object.hash(name, lastUpdated, Object.hashAll(trackers));

  LegendStat merge(LegendStat incoming) {
    final map = <String, LegendTracker>{for (final t in trackers) t.key: t};
    for (final t in incoming.trackers) {
      map[t.key] = t;
    }
    return LegendStat(
      name: name,
      trackers: map.values.toList(),
      lastUpdated: lastUpdated,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'trackers': trackers.map((t) => t.toJson()).toList(),
    if (lastUpdated != null) 'lu': lastUpdated!.millisecondsSinceEpoch,
  };

  factory LegendStat.fromJson(Map<String, dynamic> json) => LegendStat(
    name: json['name'] as String? ?? '',
    trackers: (json['trackers'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(LegendTracker.fromJson)
        .toList(),
    lastUpdated: json['lu'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['lu'] as int)
        : null,
  );
}
