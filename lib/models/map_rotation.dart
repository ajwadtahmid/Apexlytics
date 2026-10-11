class MapRotation {
  final MapMode battleRoyaleCurrent;
  final MapMode battleRoyaleNext;
  final MapMode rankedCurrent;
  final MapMode rankedNext;
  final MapMode? ltmCurrent;
  final MapMode? ltmNext;
  final MapMode? wildcardCurrent;
  final MapMode? wildcardNext;

  MapRotation({
    required this.battleRoyaleCurrent,
    required this.battleRoyaleNext,
    required this.rankedCurrent,
    required this.rankedNext,
    this.ltmCurrent,
    this.ltmNext,
    this.wildcardCurrent,
    this.wildcardNext,
  });

  /// Any block that is not a JSON object (a PHP-style empty block arrives as
  /// `[]`) counts as absent, rather than failing the whole rotation: a cast
  /// error here would blank Home for every mode and abort the background
  /// alert job.
  static Map<String, dynamic>? _object(Object? v) =>
      v is Map<String, dynamic> ? v : null;

  factory MapRotation.fromJson(Map<String, dynamic> json) {
    final battleRoyaleJson = _object(json['battle_royale']) ?? {};
    final ranked = _object(json['ranked']) ?? {};
    final ltm = _object(json['ltm']);
    final wildcard = _object(json['wildcard']);

    MapMode mode(Map<String, dynamic> block, String key) =>
        MapMode.fromJson(_object(block[key]) ?? {});

    return MapRotation(
      battleRoyaleCurrent: mode(battleRoyaleJson, 'current'),
      battleRoyaleNext: mode(battleRoyaleJson, 'next'),
      rankedCurrent: mode(ranked, 'current'),
      rankedNext: mode(ranked, 'next'),
      ltmCurrent: ltm != null ? mode(ltm, 'current') : null,
      ltmNext: ltm != null ? mode(ltm, 'next') : null,
      wildcardCurrent: wildcard != null ? mode(wildcard, 'current') : null,
      wildcardNext: wildcard != null ? mode(wildcard, 'next') : null,
    );
  }
}

class MapMode {
  final String map;
  final int remainingSecs;
  final int durationMins;
  final String asset;
  final String? eventName;

  MapMode({
    required this.map,
    required this.remainingSecs,
    required this.durationMins,
    required this.asset,
    this.eventName,
  });

  factory MapMode.fromJson(Map<String, dynamic> json) {
    final mins = (json['remainingMins'] as num?)?.toInt() ?? 0;
    // The API sometimes returns minutes only — derive seconds from minutes
    // when remainingSecs is absent.
    final secs = (json['remainingSecs'] as num?)?.toInt() ?? mins * 60;
    return MapMode(
      map: json['map'] as String? ?? 'Unknown',
      remainingSecs: secs,
      // JSON key uses PascalCase — API inconsistency, not a typo.
      durationMins: (json['DurationInMinutes'] as num?)?.toInt() ?? 0,
      asset: json['asset'] as String? ?? '',
      eventName: json['eventName'] as String?,
    );
  }
}
