import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/prefs_keys.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// How the player last set up the Pick Rate page, kept between visits.
class PickRateOptions {
  /// Show legends with too few games for a reliable average too.
  final bool showAll;

  /// Measure "good" against the player's own average RP per game, not 0.
  final bool useOwnAverage;

  /// Show the table instead of the chart.
  final bool tableView;

  const PickRateOptions({
    this.showAll = false,
    this.useOwnAverage = false,
    this.tableView = false,
  });

  PickRateOptions copyWith({
    bool? showAll,
    bool? useOwnAverage,
    bool? tableView,
  }) => PickRateOptions(
    showAll: showAll ?? this.showAll,
    useOwnAverage: useOwnAverage ?? this.useOwnAverage,
    tableView: tableView ?? this.tableView,
  );
}

final pickRateOptionsProvider =
    NotifierProvider<PickRateOptionsNotifier, PickRateOptions>(
      PickRateOptionsNotifier.new,
    );

class PickRateOptionsNotifier extends Notifier<PickRateOptions> {
  @override
  PickRateOptions build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return PickRateOptions(
      showAll: prefs.getBool(PrefsKeys.pickRateShowAll) ?? false,
      useOwnAverage: prefs.getBool(PrefsKeys.pickRateOwnAverage) ?? false,
      tableView: prefs.getBool(PrefsKeys.pickRateTable) ?? false,
    );
  }

  Future<void> setShowAll(bool value) async {
    state = state.copyWith(showAll: value);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(PrefsKeys.pickRateShowAll, value);
  }

  Future<void> setUseOwnAverage(bool value) async {
    state = state.copyWith(useOwnAverage: value);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(PrefsKeys.pickRateOwnAverage, value);
  }

  Future<void> setTableView(bool value) async {
    state = state.copyWith(tableView: value);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(PrefsKeys.pickRateTable, value);
  }
}
