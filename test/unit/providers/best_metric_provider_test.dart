import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/best_metric_provider.dart';
import 'package:apexlytics/utils/ranked/best_metric.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  test('is Total RP until one is picked', () async {
    final (container, _) = await prefsContainer();

    expect(container.read(bestMetricProvider), BestMetric.totalRp);
  });

  test('comes back as it was saved', () async {
    for (final metric in BestMetric.values) {
      final (container, _) = await prefsContainer(
        values: {PrefsKeys.bestMetric: metric.name},
      );

      expect(container.read(bestMetricProvider), metric);
    }
  });

  test('ignores a saved value that is not one of the measures', () async {
    for (final saved in ['', 'rp', 'TOTALRP', 'removed_in_a_later_version']) {
      final (container, _) = await prefsContainer(
        values: {PrefsKeys.bestMetric: saved},
      );

      expect(container.read(bestMetricProvider), BestMetric.totalRp);
    }
  });

  test('picking one changes it and keeps it', () async {
    final (container, prefs) = await prefsContainer();

    await container.read(bestMetricProvider.notifier).set(BestMetric.avgDamage);

    expect(container.read(bestMetricProvider), BestMetric.avgDamage);
    expect(prefs.getString(PrefsKeys.bestMetric), 'avgDamage');
  });
}
