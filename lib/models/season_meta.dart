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

  // "br_ranked_s29_s1" → "Season 29 (Split 1)"
  static String _parseDisplayName(String id) {
    final match = RegExp(r's(\d+)_s(\d+)$').firstMatch(id);
    if (match != null) return 'Season ${match.group(1)} (Split ${match.group(2)})';
    return id;
  }

  /// Constructs from the raw API fields (timestamps are Unix seconds).
  factory SeasonMeta.fromApi({
    required String id,
    required int startSeconds,
    required int endSeconds,
  }) =>
      SeasonMeta(
        id: id,
        displayName: _parseDisplayName(id),
        start: DateTime.fromMillisecondsSinceEpoch(startSeconds * 1000),
        end: DateTime.fromMillisecondsSinceEpoch(endSeconds * 1000),
      );

  // displayName is not serialized — it is always re-derived from id on fromJson.
  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      };

  factory SeasonMeta.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return SeasonMeta(
      id: id,
      displayName: _parseDisplayName(id),
      start: DateTime.fromMillisecondsSinceEpoch(json['start'] as int),
      end: DateTime.fromMillisecondsSinceEpoch(json['end'] as int),
    );
  }

  // displayName is excluded from equality/hashCode because it is always derived
  // from id via _parseDisplayName — two objects with identical id/start/end are
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
