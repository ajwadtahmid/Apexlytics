import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/prefs_keys.dart';
import '../utils/ranked/recap_tiles.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// The tiles the player wants on the recap card, kept between visits. Until
/// they choose, it is [defaultRecapTiles].
final recapTilesProvider = NotifierProvider<RecapTilesNotifier, Set<RecapTile>>(
  RecapTilesNotifier.new,
);

class RecapTilesNotifier extends Notifier<Set<RecapTile>> {
  @override
  Set<RecapTile> build() {
    final saved = ref
        .read(sharedPreferencesProvider)
        .getStringList(PrefsKeys.recapTiles);
    if (saved == null) return defaultRecapTiles;
    final byName = RecapTile.values.asNameMap();
    // A name from another version of the app is simply left out.
    return {
      for (final name in saved)
        if (byName[name] != null) byName[name]!,
    };
  }

  /// Turns [tile] on or off. [available] are the tiles this period can show:
  /// turning one off is refused once only [kMinRecapTiles] of them are left on.
  Future<void> toggle(RecapTile tile, Set<RecapTile> available) async {
    final on = shownRecapTiles(state, available).toSet();
    final turningOff = on.contains(tile);
    if (turningOff && on.length <= kMinRecapTiles) return;
    // Start from what is actually shown, so a stale choice for another period
    // doesn't linger, but keep the choices for tiles this period can't show.
    final next = {
      for (final t in state)
        if (!available.contains(t)) t,
      ...on,
    };
    turningOff ? next.remove(tile) : next.add(tile);
    state = next;
    await ref.read(sharedPreferencesProvider).setStringList(
      PrefsKeys.recapTiles,
      [
        for (final t in RecapTile.values)
          if (next.contains(t)) t.name,
      ],
    );
  }
}
