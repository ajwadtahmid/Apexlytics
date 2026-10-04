/// A single match from the `/games` endpoint.
///
/// The `/games` payload is a flat list of match objects. Only a subset of the
/// fields matter for the ranked breakdown; this model extracts those and
/// normalizes the messy `gameData` array (see [MatchTracker]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../constants/tracker_constants.dart';

/// RP swings at or beyond this magnitude are rank-reset artifacts
/// (end-of-split/season placement drops), not real per-game RP. Such a match
/// is excluded automatically from every stat (see
/// [RankedMatch.isAutoExcluded]); correcting its RP to a plausible value
/// brings it back.
const int kImplausibleRpThreshold = 1000;

/// Lower bound of a plausible single-game [RankedMatch.rpChange]. A drop
/// beyond this — but short of [kImplausibleRpThreshold] — is still almost
/// certainly a bad upstream value rather than a real per-game loss, and is
/// excluded the same way (see [RankedMatch.isAutoExcluded]).
const int kMinPlausibleRpChange = -250;

/// Plausible per-game ceilings for [RankedMatch.kills] and
/// [RankedMatch.damage]. A negative value or one above these is treated as
/// "not reported" (null) rather than clamped to 0, which would misrepresent
/// a played game as scoreless — see [RankedMatch.withPlausibleStats].
const int kMaxPlausibleKills = 200;
const int kMaxPlausibleDamage = 20000;

/// Upper bound for a plausible [RankedMatch.cumulativeRp]; larger restored values are
/// dropped, since the newest row's value is shown as current RP.
const int kMaxPlausibleCumulativeRp = 100000;

/// Hosts a rank badge URL may use: the current API host and the legacy one in older backups.
const Set<String> kRankImageHosts = {
  'api.apexlegendsstatus.com',
  'api.mozambiquehe.re',
};

/// Whether [url] is `https` on a [kRankImageHosts] host; a restored file must not make
/// the app fetch arbitrary addresses.
bool isTrustedRankImageUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      kRankImageHosts.contains(uri.host);
}

/// Whether [rpChange] is a reset artifact or bad upstream value rather than
/// RP the player actually moved. Plausible range is `[kMinPlausibleRpChange,
/// kImplausibleRpThreshold)`, i.e. -250..=999.
///
/// **This is the only definition** - every aggregate, Dart or SQL, must reach
/// the same verdict, or Split/Lifetime/Comparison views disagree on the same
/// rows. Queries use [kSqlPlausibleRpChange], derived from the same constants.
bool isImplausibleRpChange(int rpChange) =>
    rpChange < kMinPlausibleRpChange || rpChange >= kImplausibleRpThreshold;

/// SQL counterpart of `!`[isImplausibleRpChange], interpolated from the same
/// constants rather than restated - a hand-copied version of this is how the
/// SQL and Dart aggregates drifted before.
const String kSqlPlausibleRpChange =
    'rp_change >= $kMinPlausibleRpChange AND '
    'rp_change < $kImplausibleRpThreshold';

/// Stored columns a user may correct by hand, after which sync leaves them
/// alone. Timestamps are excluded: they derive the row's primary key, its split
/// classification and its session grouping. `length_secs` is excluded too —
/// it's not exposed for editing.
const Set<String> kEditableMatchFields = {
  'legend',
  'map_key',
  'rp_change',
  'kills',
  'damage',
};

/// Encodes [fields] as the comma-delimited, comma-terminated form stored in
/// `edited_fields`. The leading and trailing commas let SQL test membership
/// with a plain `instr(edited_fields, ',name,')`.
String? encodeEditedFields(Set<String> fields) {
  if (fields.isEmpty) return null;
  final sorted = fields.toList()..sort();
  return ',${sorted.join(',')},';
}

/// Parses the stored `edited_fields` form back into a set, ignoring names that
/// are no longer editable.
Set<String> decodeEditedFields(Object? raw) {
  if (raw is! String || raw.isEmpty) return const {};
  return {
    for (final name in raw.split(','))
      if (kEditableMatchFields.contains(name)) name,
  };
}

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

  const MatchTracker({
    required this.key,
    required this.name,
    required this.value,
  });

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

  /// The match's `gameData` trackers. Only the detail sheet reads them, so a
  /// stored row keeps the raw blob and decodes lazily instead of every row
  /// paying `jsonDecode` up front.
  List<MatchTracker> get trackers =>
      _trackers ?? (_decodedTrackers[this] ??= _decodeTrackers(_trackersJson));

  /// Parsed trackers (the API path), or null for a stored match — see
  /// [_trackersJson].
  final List<MatchTracker>? _trackers;

  /// The `trackers` column exactly as stored, decoded lazily by [trackers].
  final String? _trackersJson;

  /// The stored primary key of a match read from the store. An imported row
  /// can carry an id other than [dedupKey].
  final String? _storedId;

  /// The key to address this match by in the store.
  String get id => _storedId ?? dedupKey;

  /// Memoizes [trackers] per stored match without giving up `const`.
  static final _decodedTrackers = Expando<List<MatchTracker>>();

  /// Kills this match, or null when upstream reported no `"BR Kills"` tracker.
  /// Null means "not reported" and is excluded from kill averages; a real 0 is
  /// a played game with no kills and counts normally.
  final int? kills;

  /// Damage this match, or null when upstream reported no `"BR Damage"`
  /// tracker. Same null semantics as [kills].
  final int? damage;

  /// The split this match was classified under (e.g. `br_ranked_s29_s2`), or
  /// null/unknown if unclassified. Only ever populated by reading a persisted
  /// row back out of the local history store — a freshly API-parsed match
  /// doesn't know its season until the store derives and saves it.
  final String? seasonId;

  /// Columns the user has corrected by hand. Always empty on a freshly parsed
  /// API match; populated when reading a persisted row.
  final Set<String> editedFields;

  /// Whether the user has hand-excluded this match from every ranked
  /// calculation (summary, legends, maps, sessions, trends). Independent of
  /// [editedFields]/[kEditableMatchFields] — this isn't a value correction
  /// sync could ever contest, so it's a separate flag with its own store
  /// method rather than routed through `editMatch`. Still shows in the match
  /// History list (greyed out) so it can be found and un-excluded.
  final bool excluded;

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
    required List<MatchTracker> trackers,
    this.kills,
    this.damage,
    this.seasonId,
    this.editedFields = const {},
    this.excluded = false,
    // The fields are private but `trackers:` must stay a public named
    // parameter, which an initializing formal can't provide.
    // ignore: prefer_initializing_formals
  }) : _trackers = trackers,
       _trackersJson = null,
       _storedId = null;

  /// Shared by [fromStoredMap] and the copy methods below, so copying a
  /// stored match (e.g. to apply an edit) doesn't force its blob to decode.
  const RankedMatch._({
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
    required List<MatchTracker>? trackers,
    required String? trackersJson,
    String? storedId,
    this.kills,
    this.damage,
    this.seasonId,
    this.editedFields = const {},
    this.excluded = false,
    // Same reason as the public constructor.
    // ignore: prefer_initializing_formals
  }) : _trackers = trackers,
       // ignore: prefer_initializing_formals
       _trackersJson = trackersJson,
       // ignore: prefer_initializing_formals
       _storedId = storedId;

  /// Whether this is a Battle Royale match of any kind (ranked or pubs).
  bool get isBattleRoyale => gameMode == 'BATTLE_ROYALE';

  /// Whether this is a *ranked* match. Pubs share `gameMode == BATTLE_ROYALE`
  /// and the API exposes no explicit flag, so the only reliable signal is RP
  /// movement: a match that changed `BRScore` is ranked. Pubs (and the rare
  /// genuine ranked game that nets exactly 0 RP — unavoidable, no API signal)
  /// have `rpChange == 0` and are excluded from ranked aggregates.
  bool get isRanked => isBattleRoyale && rpChange != 0;

  /// True when this match's [rpChange] is a rank-reset artifact, or otherwise
  /// outside the plausible per-game range, rather than a real per-game swing.
  /// Such a match is left out of every stat automatically, like a hand-
  /// excluded one (see [countsTowardStats]); it is derived from the stored RP,
  /// so correcting the RP to a plausible value includes it again.
  bool get isAutoExcluded => isRanked && isImplausibleRpChange(rpChange);

  /// Whether this match feeds the stats: neither hand-[excluded] nor
  /// [isAutoExcluded]. Every aggregate — the Dart filters and the SQL
  /// `_rankedScope` alike — keys off this one definition.
  bool get countsTowardStats => !excluded && !isAutoExcluded;

  /// [rpChange], or 0 when the match doesn't [countsTowardStats]. Used in the
  /// History tab's day/group RP rollups, which still list an excluded match's
  /// row but not its RP. The raw [rpChange] is only shown on the match's own
  /// row and the RP progression graph.
  int get effectiveRpChange => countsTowardStats ? rpChange : 0;

  /// Whether any column on this match has been hand-corrected.
  bool get isEdited => editedFields.isNotEmpty;

  /// Returns a copy with [changes] (as produced by the match edit form, keyed
  /// by [kEditableMatchFields]) applied and merged into [editedFields] — the
  /// same shape the history store's `editMatch` writes to the database, so a
  /// saved correction can be reflected in an in-memory list immediately
  /// instead of waiting on the next fetch.
  ///
  /// `legend`/`map_key` check `is String`, falling back to the current
  /// value — `as String?` alone still throws on a mistyped (non-null) value
  /// like an `int`, since it only tolerates an already-null one. Unlike
  /// `kills`/`damage` below, neither field is nullable here, so a bad
  /// `changes` entry means "leave this field alone," not "clear it."
  RankedMatch withEdits(Map<String, Object?> changes) => _copy(
    legend: changes['legend'] is String ? changes['legend'] as String : null,
    mapKey: changes['map_key'] is String ? changes['map_key'] as String : null,
    rpChange: changes.containsKey('rp_change')
        ? changes['rp_change'] as int
        : null,
    kills: changes.containsKey('kills') ? (value: changes['kills'] as int?) : null,
    damage: changes.containsKey('damage')
        ? (value: changes['damage'] as int?)
        : null,
    editedFields: {...editedFields, ...changes.keys},
  );

  /// Returns a copy with [excluded] set. Kept separate from [withEdits] since
  /// exclusion isn't tracked in [editedFields] — see [excluded].
  RankedMatch withExcluded(bool excluded) => _copy(excluded: excluded);

  /// Returns a copy with [field] (or every field, if null) cleared from
  /// [editedFields] — mirrors what the history store's `clearEdits` does:
  /// only the "edited" flag is reset, values are left as-is until the next
  /// sync.
  RankedMatch withEditsCleared([String? field]) {
    final flags = {...editedFields};
    if (field == null) {
      flags.clear();
    } else {
      flags.remove(field);
    }
    return _copy(editedFields: flags);
  }

  /// Returns a copy with [kills]/[damage] nulled if negative or above
  /// [kMaxPlausibleKills]/[kMaxPlausibleDamage] — treated as "not reported",
  /// the same as when upstream never sent the tracker at all, rather than
  /// clamped to 0 (which would misrepresent a played game as scoreless).
  /// Applied to every freshly synced match before it's written to the store.
  RankedMatch withPlausibleStats() {
    final k = kills;
    final d = damage;
    final validKills = k == null || (k >= 0 && k <= kMaxPlausibleKills)
        ? k
        : null;
    final validDamage = d == null || (d >= 0 && d <= kMaxPlausibleDamage)
        ? d
        : null;
    if (validKills == k && validDamage == d) return this;
    return _copy(kills: (value: validKills), damage: (value: validDamage));
  }

  /// Copies every field. Null leaves a field as is; [kills]/[damage] are
  /// wrapped so a copy can set them to null.
  RankedMatch _copy({
    String? legend,
    String? mapKey,
    int? rpChange,
    ({int? value})? kills,
    ({int? value})? damage,
    Set<String>? editedFields,
    bool? excluded,
  }) => RankedMatch._(
    uid: uid,
    playerName: playerName,
    legend: legend ?? this.legend,
    gameMode: gameMode,
    mapKey: mapKey ?? this.mapKey,
    rpChange: rpChange ?? this.rpChange,
    cumulativeRp: cumulativeRp,
    rankImg: rankImg,
    lengthSecs: lengthSecs,
    startTime: startTime,
    endTime: endTime,
    isPartyFull: isPartyFull,
    trackers: _trackers,
    trackersJson: _trackersJson,
    storedId: _storedId,
    kills: kills != null ? kills.value : this.kills,
    damage: damage != null ? damage.value : this.damage,
    seasonId: seasonId,
    editedFields: editedFields ?? this.editedFields,
    excluded: excluded ?? this.excluded,
  );

  /// Looks up a tracker value by its stable human [name] (case-insensitive).
  /// Returns null when absent. Test-only — production code goes through
  /// [killsFrom]/[damageFrom] or the [kills]/[damage] columns instead.
  @visibleForTesting
  num? trackerValue(String name) {
    final target = name.toLowerCase();
    for (final t in trackers) {
      if (t.name.toLowerCase() == target) return t.value;
    }
    return null;
  }

  /// Kills recorded in [trackers], or null when the tracker is absent.
  static int? killsFrom(List<MatchTracker> trackers) =>
      _trackerInt(trackers, TrackerKeys.brKills);

  /// Damage recorded in [trackers], or null when the tracker is absent.
  static int? damageFrom(List<MatchTracker> trackers) =>
      _trackerInt(trackers, TrackerKeys.brDamage);

  static int? _trackerInt(List<MatchTracker> trackers, String lowerName) {
    for (final t in trackers) {
      if (t.name.toLowerCase() == lowerName) return t.value.toInt();
    }
    return null;
  }

  /// Parses a match's `gameData` array, skipping placeholder rows (key
  /// `"empty"` with no label).
  static List<MatchTracker> trackersFromJson(Object? rawData) {
    final trackers = <MatchTracker>[];
    if (rawData is List) {
      for (final e in rawData) {
        if (e is! Map<String, dynamic>) continue;
        final t = MatchTracker.fromJson(e);
        if (t.name.isEmpty) continue;
        trackers.add(t);
      }
    }
    return trackers;
  }

  factory RankedMatch.fromJson(Map<String, dynamic> json) {
    final trackers = trackersFromJson(json['gameData']);

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
      kills: killsFrom(trackers),
      damage: damageFrom(trackers),
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
  ///
  /// Only ever read when *inserting*. A stored row keeps the id it was created
  /// with, so correcting a field can never spawn a second row for one match.
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
    // Written back exactly as read for a stored match — no re-encode.
    'trackers':
        _trackersJson ??
        jsonEncode([
          for (final t in trackers)
            {'key': t.key, 'name': t.name, 'value': t.value},
        ]),
    'kills': kills,
    'damage': damage,
    'edited_fields': encodeEditedFields(editedFields),
    'excluded': excluded ? 1 : 0,
  };

  /// Decodes a stored `trackers` blob. A malformed one (hand-edited or a
  /// foreign backup) degrades to no trackers rather than throwing — caught
  /// broadly since a wrongly-typed value (e.g. `"value": "5"`) throws a
  /// TypeError, not a FormatException.
  static List<MatchTracker> _decodeTrackers(String? raw) {
    final trackers = <MatchTracker>[];
    if (raw == null || raw.isEmpty) return trackers;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded) {
          if (e is Map<String, dynamic>) {
            trackers.add(MatchTracker.fromJson(e));
          }
        }
      }
    } catch (_) {
      return const [];
    }
    return trackers;
  }

  /// A stored column as an int, or null if absent or not a number, so one
  /// bad imported row can't break every view that loads it.
  static int? _asInt(Object? v) => v is num ? v.toInt() : null;

  static String? _asString(Object? v) => v is String ? v : null;

  factory RankedMatch.fromStoredMap(Map<String, Object?> m) {
    return RankedMatch._(
      uid: _asString(m['uid']) ?? '',
      playerName: _asString(m['player_name']) ?? '',
      legend: _asString(m['legend']) ?? 'Unknown',
      gameMode: _asString(m['game_mode']) ?? 'UNKNOWN',
      mapKey: _asString(m['map_key']) ?? 'UNKNOWN',
      rpChange: _asInt(m['rp_change']) ?? 0,
      cumulativeRp: _asInt(m['cumulative_rp']) ?? 0,
      rankImg: _asString(m['rank_img']) ?? '',
      lengthSecs: _asInt(m['length_secs']) ?? 0,
      startTime: DateTime.fromMillisecondsSinceEpoch(
        _asInt(m['start_ms']) ?? 0,
        isUtc: true,
      ),
      endTime: DateTime.fromMillisecondsSinceEpoch(
        _asInt(m['end_ms']) ?? 0,
        isUtc: true,
      ),
      isPartyFull: _asInt(m['is_party_full']) == 1,
      trackers: null,
      trackersJson: _asString(m['trackers']),
      storedId: _asString(m['id']),
      // The stored columns win over the trackers blob: they carry any hand
      // correction, and the blob stays as upstream sent it.
      kills: _asInt(m['kills']),
      damage: _asInt(m['damage']),
      seasonId: _asString(m['season_id']),
      editedFields: decodeEditedFields(m['edited_fields']),
      excluded: _asInt(m['excluded']) == 1,
    );
  }
}
