import '../constants/map_constants.dart';

class SeasonalMaps {
  /// Prefs key the cyclic rotation order is cached under, shared by the
  /// foreground provider and the headless background fetch isolate.
  static const String cacheKey = 'seasonal_maps_cache';

  final List<AppMap> ranked;
  final List<AppMap> pubs;

  SeasonalMaps({required this.ranked, required this.pubs});

  /// The rotation order as plain map names, for notification copy.
  List<String> get rankedNames => ranked.map((m) => m.name).toList();
  List<String> get pubsNames => pubs.map((m) => m.name).toList();

  factory SeasonalMaps.fromJson(Map<String, dynamic> json) {
    final ranked = (json['ranked'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            .map((m) => AppMap(
                  id: m['id'] as String? ?? '',
                  name: m['name'] as String? ?? '',
                ))
            .toList() ??
        [];
    final pubs = (json['pubs'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            .map((m) => AppMap(
                  id: m['id'] as String? ?? '',
                  name: m['name'] as String? ?? '',
                ))
            .toList() ??
        [];
    return SeasonalMaps(ranked: ranked, pubs: pubs);
  }

  Map<String, dynamic> toJson() => {
        'ranked': ranked.map((m) => {'id': m.id, 'name': m.name}).toList(),
        'pubs': pubs.map((m) => {'id': m.id, 'name': m.name}).toList(),
      };
}
