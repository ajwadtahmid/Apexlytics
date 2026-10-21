import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/legend_constants.dart' show canonicalLegendName;
import '../constants/map_constants.dart' show canonicalMapKey;
import '../constants/prefs_keys.dart';
import '../utils/ranked/entity_trend_window.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// What a legend's own trend window is filed under.
String legendTrendKey(String legend) => 'legend:${canonicalLegendName(legend)}';

/// What a map's own trend window is filed under.
String mapTrendKey(String mapKey) => 'map:${canonicalMapKey(mapKey)}';

/// The legends and maps the player gave a trend window of their own, as a game
/// count each (see [isTrendChoice]) or [kEntityTrendAuto]; everything
/// else follows the window chosen for all of them (see
/// [entityTrendWindowProvider]). Kept
/// between visits, on this device only. Filed by [legendTrendKey] and
/// [mapTrendKey], not by profile: it is how the player likes to look at a
/// legend, not data about one player.
final entityTrendOverridesProvider =
    NotifierProvider<EntityTrendOverridesNotifier, Map<String, int>>(
      EntityTrendOverridesNotifier.new,
    );

class EntityTrendOverridesNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    final raw = ref
        .read(sharedPreferencesProvider)
        .getString(PrefsKeys.entityTrendOverrides);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final e in decoded.entries)
          if (e.key is String &&
              e.value is int &&
              isTrendChoice(e.value as int))
            e.key as String: e.value as int,
      };
    } catch (_) {
      // Damaged text reads as no overrides rather than failing the sheet.
      return const {};
    }
  }

  /// Gives [key] its own window of [games] (see [isTrendChoice]), or
  /// [kEntityTrendAuto]. A count that is not [isTrendChoice] is ignored, since
  /// it would only be dropped at the next launch.
  Future<void> set(String key, int games) async {
    if (!isTrendChoice(games)) return;
    await _save({...state, key: games});
  }

  /// Takes [key] back to following the window chosen for everything.
  Future<void> clear(String key) => _save({
    for (final e in state.entries)
      if (e.key != key) e.key: e.value,
  });

  Future<void> _save(Map<String, int> next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    if (next.isEmpty) {
      await prefs.remove(PrefsKeys.entityTrendOverrides);
    } else {
      await prefs.setString(PrefsKeys.entityTrendOverrides, jsonEncode(next));
    }
  }
}
