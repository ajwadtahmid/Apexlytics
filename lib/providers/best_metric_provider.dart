import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/prefs_keys.dart';
import '../utils/ranked/best_metric.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// What makes a legend or map "best", as the player last chose it. Kept between
/// visits, and read everywhere a best or worst is named, so the Overview, the
/// Recap and the drill-down pages never disagree.
final bestMetricProvider = NotifierProvider<BestMetricNotifier, BestMetric>(
  BestMetricNotifier.new,
);

class BestMetricNotifier extends Notifier<BestMetric> {
  @override
  BestMetric build() {
    final saved = ref
        .read(sharedPreferencesProvider)
        .getString(PrefsKeys.bestMetric);
    return BestMetric.values.asNameMap()[saved] ?? kDefaultBestMetric;
  }

  /// Picks [metric] and keeps it.
  Future<void> set(BestMetric metric) async {
    state = metric;
    await ref
        .read(sharedPreferencesProvider)
        .setString(PrefsKeys.bestMetric, metric.name);
  }
}
