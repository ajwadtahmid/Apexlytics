import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/entity_trend_window_provider.dart';
import 'package:apexlytics/utils/ranked/entity_trend_window.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  test('is Auto until one is picked', () async {
    final (container, _) = await prefsContainer();

    expect(container.read(entityTrendWindowProvider), kEntityTrendAuto);
  });

  test('comes back as it was saved', () async {
    for (final saved in [kEntityTrendAuto, ...kEntityTrendPresets]) {
      final (container, _) = await prefsContainer(
        values: {PrefsKeys.entityTrendGames: saved},
      );

      expect(container.read(entityTrendWindowProvider), saved);
    }
  });

  test('ignores a saved value that is not one of the choices', () async {
    for (final saved in [3, 4, -1, 1001]) {
      final (container, _) = await prefsContainer(
        values: {PrefsKeys.entityTrendGames: saved},
      );

      expect(container.read(entityTrendWindowProvider), kEntityTrendAuto);
    }
  });

  test('picking one changes it and keeps it', () async {
    final (container, prefs) = await prefsContainer();

    await container.read(entityTrendWindowProvider.notifier).set(25);

    expect(container.read(entityTrendWindowProvider), 25);
    expect(prefs.getInt(PrefsKeys.entityTrendGames), 25);
  });

  test('a count typed in is kept, from 5 to 1,000', () async {
    for (final saved in [5, 37, 250, 1000]) {
      final (container, prefs) = await prefsContainer();

      await container.read(entityTrendWindowProvider.notifier).set(saved);

      expect(container.read(entityTrendWindowProvider), saved);
      expect(prefs.getInt(PrefsKeys.entityTrendGames), saved);
    }
  });

  test(
    'a count that is not a choice is ignored, in memory and on disk',
    () async {
      for (final bad in [-1, 1, 4, 1001, 50000]) {
        final (container, prefs) = await prefsContainer(
          values: {PrefsKeys.entityTrendGames: 25},
        );

        await container.read(entityTrendWindowProvider.notifier).set(bad);

        expect(container.read(entityTrendWindowProvider), 25, reason: '$bad');
        expect(prefs.getInt(PrefsKeys.entityTrendGames), 25, reason: '$bad');
      }
    },
  );

  test('Auto is kept too', () async {
    final (container, prefs) = await prefsContainer(
      values: {PrefsKeys.entityTrendGames: 50},
    );

    await container
        .read(entityTrendWindowProvider.notifier)
        .set(kEntityTrendAuto);

    expect(container.read(entityTrendWindowProvider), kEntityTrendAuto);
    expect(prefs.getInt(PrefsKeys.entityTrendGames), kEntityTrendAuto);
  });
}
