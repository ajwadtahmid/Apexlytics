class SeasonMeta {
  final String id;
  final String displayName;
  final DateTime start;
  final DateTime end;

  const SeasonMeta({
    required this.id,
    required this.displayName,
    required this.start,
    required this.end,
  });

  static final _splitIdPattern = RegExp(r's(\d+)_s(\d+)$');

  /// Whether [id] names a real ranked split (`br_ranked_s29_s1`), not a
  /// placeholder the API sometimes sends instead (e.g. `__other__`). Only a
  /// real split may be stored or used to classify matches — a placeholder's
  /// window can overlap the real one's, permanently misfiling a match.
  static bool isSplitId(String id) => _splitIdPattern.hasMatch(id);

  // "br_ranked_s29_s1" → "Season 29 (Split 1)"
  //
  // An id that doesn't match falls back to "Other" rather than the raw id —
  // the upstream ranked API is known to send non-split placeholder ids (e.g.
  // "__other__") verbatim through `rankedSeason`, and showing that raw,
  // underscored string to the user is worse than a generic label for
  // whatever this season actually is.
  //
  // Public (not just used by [fromApi]/[fromJson]) so `buildSplitBuckets`
  // can apply the same rule to a bare season id that has no [SeasonMeta] at
  // all — a match's persisted `season_id` with nothing ever learned for it
  // would otherwise show that raw id too, via a completely different
  // fallback path this class doesn't control.
  static String parseDisplayName(String id) {
    final match = _splitIdPattern.firstMatch(id);
    if (match != null) {
      return 'Season ${match.group(1)} (Split ${match.group(2)})';
    }
    return 'Other';
  }

  /// Constructs from the raw API fields (timestamps are Unix seconds).
  factory SeasonMeta.fromApi({
    required String id,
    required int startSeconds,
    required int endSeconds,
  }) => SeasonMeta(
    id: id,
    displayName: parseDisplayName(id),
    start: DateTime.fromMillisecondsSinceEpoch(startSeconds * 1000),
    end: DateTime.fromMillisecondsSinceEpoch(endSeconds * 1000),
  );

  // displayName is not serialized — it is always re-derived from id on fromJson.
  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
  };

  /// Returns null rather than throwing when [json] is missing a required
  /// field or has the wrong type for one — a season entry corrupted by a
  /// hand-edited or foreign backup file should be skipped by the caller
  /// (dropping one split), not take down every season the app knows about.
  static SeasonMeta? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final start = json['start'];
    final end = json['end'];
    if (id is! String || id.isEmpty) return null;
    if (start is! num || end is! num) return null;
    return SeasonMeta(
      id: id,
      displayName: parseDisplayName(id),
      start: DateTime.fromMillisecondsSinceEpoch(start.toInt()),
      end: DateTime.fromMillisecondsSinceEpoch(end.toInt()),
    );
  }

  // displayName is excluded from equality/hashCode because it is always derived
  // from id via parseDisplayName — two objects with identical id/start/end are
  // always equal, regardless of how displayName was constructed.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeasonMeta &&
          id == other.id &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(id, start, end);
}
