/// A single match from the `/games` endpoint.
///
/// The `/games` payload is a flat list of match objects. Only a subset of the
/// fields matter for the ranked breakdown; this model extracts those and
/// normalizes the messy `gameData` array (see [MatchTracker]).
library;

import 'dart:convert';

/// One entry from a match's `gameData` array.
///
/// The `key` is unstable — the same stat shows up under different keys across
/// players (`kills` vs `specialEvent_kills`, both labelled `"BR Kills"`). Always
/// match on [name] (the human label), never [key].
class MatchTracker {
  /// Raw API key — unstable across players. Do not match on this.
  final String key;

  /// Human-readable label, e.g. `"BR Kills"`, `"BR Damage"`,
  /// `"Tactical: Nitro Gates Used"`. Stable; match on this.
  final String name;

  final num value;

  const MatchTracker({required this.key, required this.name, required this.value});

  factory MatchTracker.fromJson(Map<String, dynamic> json) => MatchTracker(
    key: json['key'] as String? ?? '',
    name: (json['name'] as String? ?? '').trim(),
    value: (json['value'] as num?) ?? 0,
  );
}

class RankedMatch {
  final String uid;
  final String playerName;
  final String legend; // legendPlayed
  final String gameMode; // BATTLE_ROYALE / UNKNOWN
  final String mapKey; // raw rotation key, e.g. "olympus_rotation"
  final int rpChange; // BRScoreChange — RP gained/lost this match
  final int cumulativeRp; // BRScore — running total after this match
  final String rankImg; // BRRankImg — tier badge URL
  final int lengthSecs; // gameLengthSecs
  final DateTime startTime; // gameStartTimestamp (UTC)
  final DateTime endTime; // gameEndTimestamp (UTC)
  final bool isPartyFull;
  final List<MatchTracker> trackers;

  const RankedMatch({
    required this.uid,
    required this.playerName,
    required this.legend,
    required this.gameMode,
    required this.mapKey,
    required this.rpChange,
    required this.cumulativeRp,
    required this.rankImg,
    required this.lengthSecs,
    required this.startTime,
    required this.endTime,
    required this.isPartyFull,
    required this.trackers,
  });

  /// Whether this is a Battle Royale match of any kind (ranked or pubs).
  bool get isBattleRoyale => gameMode == 'BATTLE_ROYALE';

  /// Whether this is a *ranked* match. Pubs share `gameMode == BATTLE_ROYALE`
  /// and the API exposes no explicit flag, so the only reliable signal is RP
  /// movement: a match that changed `BRScore` is ranked. Pubs (and the rare
  /// genuine ranked game that nets exactly 0 RP — unavoidable, no API signal)
  /// have `rpChange == 0` and are excluded from ranked aggregates.
  bool get isRanked => isBattleRoyale && rpChange != 0;

  /// Looks up a tracker value by its stable human [name] (case-insensitive).
  /// Returns null when the match didn't carry that tracker.
  num? trackerValue(String name) {
    final target = name.toLowerCase();
    for (final t in trackers) {
      if (t.name.toLowerCase() == target) return t.value;
    }
    return null;
  }

  int get kills => trackerValue('BR Kills')?.toInt() ?? 0;
  int get damage => trackerValue('BR Damage')?.toInt() ?? 0;

  factory RankedMatch.fromJson(Map<String, dynamic> json) {
    final rawData = json['gameData'];
    final trackers = <MatchTracker>[];
    if (rawData is List) {
      for (final e in rawData) {
        if (e is! Map<String, dynamic>) continue;
        final t = MatchTracker.fromJson(e);
        // Skip placeholder/empty rows (key "empty" with no label).
        if (t.name.isEmpty) continue;
        trackers.add(t);
      }
    }

    return RankedMatch(
      uid: json['uid']?.toString() ?? '',
      playerName: json['name'] as String? ?? '',
      legend: json['legendPlayed'] as String? ?? 'Unknown',
      gameMode: json['gameMode'] as String? ?? 'UNKNOWN',
      mapKey: json['map'] as String? ?? 'UNKNOWN',
      rpChange: (json['BRScoreChange'] as num?)?.toInt() ?? 0,
      cumulativeRp: (json['BRScore'] as num?)?.toInt() ?? 0,
      rankImg: json['BRRankImg'] as String? ?? '',
      lengthSecs: (json['gameLengthSecs'] as num?)?.toInt() ?? 0,
      startTime: _epochToUtc(json['gameStartTimestamp']),
      endTime: _epochToUtc(json['gameEndTimestamp']),
      isPartyFull: json['isPartyFull'] as bool? ?? false,
      trackers: trackers,
    );
  }

  /// Parses the whole `/games` list response into matches, skipping malformed
  /// entries instead of throwing on a single bad row.
  static List<RankedMatch> listFromJson(List<dynamic> json) {
    final out = <RankedMatch>[];
    for (final e in json) {
      if (e is Map<String, dynamic>) out.add(RankedMatch.fromJson(e));
    }
    return out;
  }

  /// Epoch seconds → UTC [DateTime]. Convert to local before any time-of-day
  /// bucketing.
  static DateTime _epochToUtc(dynamic raw) {
    final secs = (raw as num?)?.toInt() ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
  }

  /// Stable, unique key for persistence — one match per player per start time.
  /// The API has no match ID, so `uid` + start-second identifies a match.
  String get dedupKey => '${uid}_${startTime.millisecondsSinceEpoch ~/ 1000}';

  /// Flat column map for the local database (and the export/import JSON).
  /// Trackers are stored as a JSON string; cosmetics/Arenas fields are dropped.
  Map<String, Object?> toStoredMap() => {
    'id': dedupKey,
    'uid': uid,
    'player_name': playerName,
    'legend': legend,
    'game_mode': gameMode,
    'map_key': mapKey,
    'rp_change': rpChange,
    'cumulative_rp': cumulativeRp,
    'rank_img': rankImg,
    'length_secs': lengthSecs,
    'start_ms': startTime.millisecondsSinceEpoch,
    'end_ms': endTime.millisecondsSinceEpoch,
    'is_party_full': isPartyFull ? 1 : 0,
    'trackers': jsonEncode([
      for (final t in trackers) {'key': t.key, 'name': t.name, 'value': t.value},
    ]),
  };

  factory RankedMatch.fromStoredMap(Map<String, Object?> m) {
    final trackers = <MatchTracker>[];
    final raw = m['trackers'];
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded) {
          if (e is Map<String, dynamic>) trackers.add(MatchTracker.fromJson(e));
        }
      }
    }
    return RankedMatch(
      uid: m['uid'] as String? ?? '',
      playerName: m['player_name'] as String? ?? '',
      legend: m['legend'] as String? ?? 'Unknown',
      gameMode: m['game_mode'] as String? ?? 'UNKNOWN',
      mapKey: m['map_key'] as String? ?? 'UNKNOWN',
      rpChange: (m['rp_change'] as num?)?.toInt() ?? 0,
      cumulativeRp: (m['cumulative_rp'] as num?)?.toInt() ?? 0,
      rankImg: m['rank_img'] as String? ?? '',
      lengthSecs: (m['length_secs'] as num?)?.toInt() ?? 0,
      startTime: DateTime.fromMillisecondsSinceEpoch(
        (m['start_ms'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      endTime: DateTime.fromMillisecondsSinceEpoch(
        (m['end_ms'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      isPartyFull: (m['is_party_full'] as num?)?.toInt() == 1,
      trackers: trackers,
    );
  }
}
