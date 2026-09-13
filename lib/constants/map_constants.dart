class AppMap {
  final String id;
  final String name; // exact string returned by the ALS API

  const AppMap({required this.id, required this.name});
}

// Master list — battle royale maps. Add new entries here when Respawn ships a new map.
const List<AppMap> kBattleRoyaleMaps = [
  AppMap(id: '1', name: "Kings Canyon"),
  AppMap(id: '2', name: "World's Edge"),
  AppMap(id: '3', name: "Olympus"),
  AppMap(id: '4', name: "Storm Point"),
  AppMap(id: '5', name: "Broken Moon"),
  AppMap(id: '6', name: "E-District"),
];
