import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/recap_tiles_provider.dart';
import 'package:apexlytics/utils/ranked/recap_tiles.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  final all = RecapTile.values.toSet();

  test(
    'starts with the defaults, which leave out the win rate and RP per game',
    () async {
      final (container, _) = await prefsContainer();

      final tiles = container.read(recapTilesProvider);

      expect(tiles, defaultRecapTiles);
      expect(tiles, isNot(contains(RecapTile.winRate)));
      expect(tiles, isNot(contains(RecapTile.rpPerGame)));
    },
  );

  test(
    'comes back as it was saved, and drops names it no longer knows',
    () async {
      final (container, _) = await prefsContainer(
        values: {
          // "winStreak" and "vsLastSplit" were tiles of an earlier version.
          PrefsKeys.recapTiles: [
            'games',
            'winRate',
            'winStreak',
            'vsLastSplit',
          ],
        },
      );

      expect(container.read(recapTilesProvider), {
        RecapTile.games,
        RecapTile.winRate,
      });
    },
  );

  test('turning a tile on adds it, and keeps it, in card order', () async {
    final (container, prefs) = await prefsContainer();

    await container
        .read(recapTilesProvider.notifier)
        .toggle(RecapTile.rpPerGame, all);
    await container
        .read(recapTilesProvider.notifier)
        .toggle(RecapTile.winRate, all);

    expect(container.read(recapTilesProvider), contains(RecapTile.winRate));
    expect(prefs.getStringList(PrefsKeys.recapTiles), [
      'games',
      'peakRp',
      'kills',
      'damage',
      'bestSession',
      'timePlayed',
      'bestLegend',
      'bestMap',
      'winRate',
      'rpPerGame',
    ]);
  });

  test('turning a tile off removes it, and keeps that', () async {
    final (container, prefs) = await prefsContainer();

    await container
        .read(recapTilesProvider.notifier)
        .toggle(RecapTile.kills, all);

    expect(
      container.read(recapTilesProvider),
      isNot(contains(RecapTile.kills)),
    );
    expect(prefs.getStringList(PrefsKeys.recapTiles), isNot(contains('kills')));
  });

  test('will not turn off the last two', () async {
    final (container, prefs) = await prefsContainer(
      values: {
        PrefsKeys.recapTiles: ['games', 'peakRp'],
      },
    );

    await container
        .read(recapTilesProvider.notifier)
        .toggle(RecapTile.games, all);

    expect(container.read(recapTilesProvider), {
      RecapTile.games,
      RecapTile.peakRp,
    });
    expect(prefs.getStringList(PrefsKeys.recapTiles), ['games', 'peakRp']);
  });

  test(
    'counts only the tiles this period can show towards the least',
    () async {
      // Two of the three chosen can be shown, so neither may be turned off.
      final (container, _) = await prefsContainer(
        values: {
          PrefsKeys.recapTiles: ['games', 'peakRp', 'bestLegend'],
        },
      );
      final available = all.difference({RecapTile.bestLegend});

      await container
          .read(recapTilesProvider.notifier)
          .toggle(RecapTile.games, available);

      expect(container.read(recapTilesProvider), contains(RecapTile.games));
    },
  );

  test('keeps a choice for a tile this period cannot show', () async {
    final (container, prefs) = await prefsContainer(
      values: {
        PrefsKeys.recapTiles: ['games', 'peakRp', 'kills', 'bestLegend'],
      },
    );
    final available = all.difference({RecapTile.bestLegend});

    await container
        .read(recapTilesProvider.notifier)
        .toggle(RecapTile.kills, available);

    // Kills is off; the best legend, which this period had no say in, stays on
    // for a period that can show it.
    expect(prefs.getStringList(PrefsKeys.recapTiles), [
      'games',
      'peakRp',
      'bestLegend',
    ]);
  });

  test(
    'a choice with too few tiles that can be shown starts from the defaults',
    () async {
      final (container, _) = await prefsContainer(
        values: {
          PrefsKeys.recapTiles: ['bestLegend', 'rpPerGame'],
        },
      );
      final available = all.difference({
        RecapTile.bestLegend,
        RecapTile.rpPerGame,
      });

      await container
          .read(recapTilesProvider.notifier)
          .toggle(RecapTile.games, available);

      final tiles = container.read(recapTilesProvider);
      expect(tiles, isNot(contains(RecapTile.games)));
      expect(tiles, contains(RecapTile.peakRp));
      // The choices for tiles it couldn't show were not lost.
      expect(tiles, containsAll([RecapTile.bestLegend, RecapTile.rpPerGame]));
    },
  );
}
