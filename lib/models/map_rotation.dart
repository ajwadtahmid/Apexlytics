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

  factory MapRotation.fromJson(Map<String, dynamic> json) {
    final battleRoyaleJson =
        json['battle_royale'] as Map<String, dynamic>? ?? {};
    final ranked = json['ranked'] as Map<String, dynamic>? ?? {};
    final ltm = json['ltm'] as Map<String, dynamic>?;
    final wildcard = json['wildcard'] as Map<String, dynamic>?;

    return MapRotation(
      battleRoyaleCurrent: MapMode.fromJson(
        battleRoyaleJson['current'] as Map<String, dynamic>? ?? {},
      ),
      battleRoyaleNext: MapMode.fromJson(
        battleRoyaleJson['next'] as Map<String, dynamic>? ?? {},
      ),
      rankedCurrent: MapMode.fromJson(
        ranked['current'] as Map<String, dynamic>? ?? {},
      ),
      rankedNext: MapMode.fromJson(
        ranked['next'] as Map<String, dynamic>? ?? {},
      ),
      ltmCurrent: ltm != null
          ? MapMode.fromJson(ltm['current'] as Map<String, dynamic>? ?? {})
          : null,
      ltmNext: ltm != null
          ? MapMode.fromJson(ltm['next'] as Map<String, dynamic>? ?? {})
          : null,
      wildcardCurrent: wildcard != null
          ? MapMode.fromJson(wildcard['current'] as Map<String, dynamic>? ?? {})
          : null,
      wildcardNext: wildcard != null
          ? MapMode.fromJson(wildcard['next'] as Map<String, dynamic>? ?? {})
          : null,
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
