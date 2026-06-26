import '../utils/formatting/map_name_utils.dart';

/// Canonical metadata for a ranked map (display name + splash asset).
class RankedMapInfo {
  final String name;
  final String asset;
  const RankedMapInfo({required this.name, required this.asset});
}

/// Ranked maps keyed by the rotation key with `_rotation` stripped
/// (`e_district_rotation` → `e_district`). Mirrors the legend/weapon const
/// pattern so display names and images live in one place.
const Map<String, RankedMapInfo> kRankedMaps = {
  'kings_canyon':
      RankedMapInfo(name: 'Kings Canyon', asset: 'assets/maps/kings_canyon.webp'),
  'worlds_edge':
      RankedMapInfo(name: "World's Edge", asset: 'assets/maps/worlds_edge.webp'),
  'olympus': RankedMapInfo(name: 'Olympus', asset: 'assets/maps/olympus.webp'),
  'storm_point':
      RankedMapInfo(name: 'Storm Point', asset: 'assets/maps/storm_point.webp'),
  'broken_moon':
      RankedMapInfo(name: 'Broken Moon', asset: 'assets/maps/broken_moon.webp'),
  // The API uses "edistrict" (no underscore); keep both spellings mapped.
  'edistrict':
      RankedMapInfo(name: 'E-District', asset: 'assets/maps/e_district.webp'),
  'e_district':
      RankedMapInfo(name: 'E-District', asset: 'assets/maps/e_district.webp'),
};

String _baseKey(String mapKey) {
  final k = mapKey.trim().toLowerCase();
  return k.endsWith('_rotation')
      ? k.substring(0, k.length - '_rotation'.length)
      : k;
}

/// Whether [mapKey] is the API's catch-all "unknown" map (excluded from map
/// breakdowns — there's nothing meaningful to show for it).
bool isUnknownMapKey(String mapKey) {
  final k = mapKey.trim();
  return k.isEmpty || k.toUpperCase() == 'UNKNOWN';
}

RankedMapInfo? rankedMapInfo(String mapKey) => kRankedMaps[_baseKey(mapKey)];

/// Display name from the const, falling back to a title-cased key.
String rankedMapName(String mapKey) =>
    rankedMapInfo(mapKey)?.name ?? formatRotationMapName(mapKey);

/// Splash asset path, or null when there's no bundled image for the map.
String? rankedMapAsset(String mapKey) => rankedMapInfo(mapKey)?.asset;
