import '../utils/formatting/map_name_utils.dart';

/// One Battle Royale map as reported by the `/maps` API's live rotation
/// response — the *current pool*, not the static catalog below. Populated at
/// runtime from `SeasonalMaps.ranked`/`.pubs`; `id` is whatever the server
/// assigns, used only for change-detection against the cached copy.
class AppMap {
  final String id;
  final String name; // exact string returned by the ALS API

  const AppMap({required this.id, required this.name});
}

/// Canonical metadata for a Battle Royale map: id, display name, and splash
/// asset. Mirrors the legend/weapon const pattern so this data lives in one
/// place.
class BattleRoyaleMapInfo {
  final String id;
  final String name;
  final String asset;
  const BattleRoyaleMapInfo({
    required this.id,
    required this.name,
    required this.asset,
  });
}

/// The master Battle Royale map catalog, keyed by the rotation key with
/// `_rotation` stripped (`kings_canyon_rotation` → `kings_canyon`). This is
/// the single source of truth for every map-related lookup in the app —
/// display names, splash assets, canonical grouping for the ranked
/// breakdown, and the canonical ordering used by the map-alerts picker.
///
/// Add new entries here when Respawn ships a new map — there is nowhere else
/// that needs updating.
const Map<String, BattleRoyaleMapInfo> kBattleRoyaleMaps = {
  'kings_canyon': BattleRoyaleMapInfo(
    id: '1',
    name: 'Kings Canyon',
    asset: 'assets/maps/kings_canyon.webp',
  ),
  'worlds_edge': BattleRoyaleMapInfo(
    id: '2',
    name: "World's Edge",
    asset: 'assets/maps/worlds_edge.webp',
  ),
  'olympus': BattleRoyaleMapInfo(
    id: '3',
    name: 'Olympus',
    asset: 'assets/maps/olympus.webp',
  ),
  'storm_point': BattleRoyaleMapInfo(
    id: '4',
    name: 'Storm Point',
    asset: 'assets/maps/storm_point.webp',
  ),
  'broken_moon': BattleRoyaleMapInfo(
    id: '5',
    name: 'Broken Moon',
    asset: 'assets/maps/broken_moon.webp',
  ),
  // The API's confirmed spelling is "edistrict" (no underscore) — no other
  // spelling is mapped here on purpose.
  'edistrict': BattleRoyaleMapInfo(
    id: '6',
    name: 'E-District',
    asset: 'assets/maps/e_district.webp',
  ),
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

BattleRoyaleMapInfo? battleRoyaleMapInfo(String mapKey) =>
    kBattleRoyaleMaps[_baseKey(mapKey)];

/// Display name from the const, falling back to a title-cased key.
String battleRoyaleMapName(String mapKey) =>
    battleRoyaleMapInfo(mapKey)?.name ?? formatRotationMapName(mapKey);

/// Splash asset path, or null when there's no bundled image for the map.
String? battleRoyaleMapAsset(String mapKey) =>
    battleRoyaleMapInfo(mapKey)?.asset;

/// A stable grouping key for [mapKey]: the canonical display name when the
/// key is known, otherwise [_baseKey] so an unknown key at least normalizes
/// case and a trailing `_rotation`. Never shown to the user — use
/// [battleRoyaleMapName] for display.
///
/// This is what [mapBreakdowns] groups by, mirroring the canonicalization
/// [legendMapBreakdowns] already applies — a raw-key grouping would split one
/// map into several identically-labelled rows.
String canonicalMapKey(String mapKey) =>
    battleRoyaleMapInfo(mapKey)?.name ?? _baseKey(mapKey);

/// Every raw `map_key` spelling that shares [mapKey]'s [canonicalMapKey],
/// including a `_rotation`-suffixed form. SQL can't canonicalize on read the
/// way Dart can, so a query that needs "every match for this map" (e.g.
/// `RankedHistoryStore.matchesForMap`) needs the concrete list of raw values
/// to match against instead of a single equality check.
List<String> battleRoyaleMapKeyVariants(String mapKey) {
  final info = battleRoyaleMapInfo(mapKey);
  if (info == null) return [mapKey];
  final bases = kBattleRoyaleMaps.entries
      .where((e) => e.value.name == info.name)
      .map((e) => e.key);
  return [
    for (final base in bases) ...[base, '${base}_rotation'],
  ];
}
