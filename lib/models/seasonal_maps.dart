import '../constants/map_constants.dart';
import '../utils/formatting/json_utils.dart';

class SeasonalMaps {
  final List<AppMap> ranked;
  final List<AppMap> pubs;

  SeasonalMaps({required this.ranked, required this.pubs});

  /// The rotation order as plain map names, for notification copy.
  List<String> get rankedNames => ranked.map((m) => m.name).toList();
  List<String> get pubsNames => pubs.map((m) => m.name).toList();

  factory SeasonalMaps.fromJson(Map<String, dynamic> json) {
    return SeasonalMaps(
      ranked: _parseMaps(json['ranked']),
      pubs: _parseMaps(json['pubs']),
    );
  }

  /// The maps in [raw], skipping anything that isn't a map entry.
  static List<AppMap> _parseMaps(Object? raw) {
    final out = <AppMap>[];
    for (final e in asList(raw) ?? const []) {
      final m = asObject(e);
      if (m == null) continue;
      out.add(
        AppMap(id: asString(m['id']) ?? '', name: asString(m['name']) ?? ''),
      );
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'ranked': ranked.map((m) => {'id': m.id, 'name': m.name}).toList(),
    'pubs': pubs.map((m) => {'id': m.id, 'name': m.name}).toList(),
  };
}
