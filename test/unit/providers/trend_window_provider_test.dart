import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/trend_window_provider.dart';
import 'package:apexlytics/utils/ranked/performance_insights.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  test('is five until one is picked', () async {
    final (container, _) = await prefsContainer();

    expect(container.read(trendWindowProvider), kDefaultTrendWindow);
    expect(kDefaultTrendWindow, 5);
  });

  test('comes back as it was saved', () async {
    for (final saved in [...kTrendWindowPresets, kTrendWindowAll]) {
      final (container, _) = await prefsContainer(
        values: {PrefsKeys.trendSessionsShown: saved},
      );

      expect(container.read(trendWindowProvider), saved);
    }
  });

  test('ignores a saved value that is not one of the counts', () async {
    for (final saved in [7, -1, 100]) {
      final (container, _) = await prefsContainer(
        values: {PrefsKeys.trendSessionsShown: saved},
      );

      expect(container.read(trendWindowProvider), kDefaultTrendWindow);
    }
  });

  test('picking one changes it and keeps it', () async {
    final (container, prefs) = await prefsContainer();

    await container.read(trendWindowProvider.notifier).set(25);

    expect(container.read(trendWindowProvider), 25);
    expect(prefs.getInt(PrefsKeys.trendSessionsShown), 25);
  });

  test('All is kept too', () async {
    final (container, prefs) = await prefsContainer(
      values: {PrefsKeys.trendSessionsShown: 10},
    );

    await container.read(trendWindowProvider.notifier).set(kTrendWindowAll);

    expect(container.read(trendWindowProvider), kTrendWindowAll);
    expect(prefs.getInt(PrefsKeys.trendSessionsShown), 0);
  });
}
