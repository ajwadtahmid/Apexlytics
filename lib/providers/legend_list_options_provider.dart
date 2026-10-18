import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/legend_constants.dart';
import '../constants/prefs_keys.dart';
import '../utils/tracking/legend_stat_sort.dart';
import 'settings_provider.dart' show sharedPreferencesProvider;

/// How the player last set up the Legends tab, kept between visits.
class LegendListOptions {
  final LegendStatSort sort;

  /// The order turned round, such as the smallest figure first.
  final bool reversed;

  /// Only legends of this role; null for all of them.
  final LegendRole? role;

  const LegendListOptions({
    this.sort = LegendStatSort.recent,
    this.reversed = false,
    this.role,
  });

  LegendListOptions copyWith({
    LegendStatSort? sort,
    bool? reversed,
    LegendRole? Function()? role,
  }) => LegendListOptions(
    sort: sort ?? this.sort,
    reversed: reversed ?? this.reversed,
    role: role != null ? role() : this.role,
  );
}

final legendListOptionsProvider =
    NotifierProvider<LegendListOptionsNotifier, LegendListOptions>(
      LegendListOptionsNotifier.new,
    );

class LegendListOptionsNotifier extends Notifier<LegendListOptions> {
  @override
  LegendListOptions build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final sort = prefs.getString(PrefsKeys.legendSort);
    final role = prefs.getString(PrefsKeys.legendRoleFilter);
    return LegendListOptions(
      sort: LegendStatSort.values.asNameMap()[sort] ?? LegendStatSort.recent,
      reversed: prefs.getBool(PrefsKeys.legendSortReversed) ?? false,
      role: LegendRole.values.asNameMap()[role],
    );
  }

  /// Orders by [sort], its natural end first. Choosing the order already in
  /// use turns it round instead.
  Future<void> choose(LegendStatSort sort) async {
    final reversed = sort == state.sort && !state.reversed;
    state = state.copyWith(sort: sort, reversed: reversed);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(PrefsKeys.legendSort, sort.name);
    await prefs.setBool(PrefsKeys.legendSortReversed, reversed);
  }

  Future<void> setRole(LegendRole? role) async {
    state = state.copyWith(role: () => role);
    final prefs = ref.read(sharedPreferencesProvider);
    if (role == null) {
      await prefs.remove(PrefsKeys.legendRoleFilter);
    } else {
      await prefs.setString(PrefsKeys.legendRoleFilter, role.name);
    }
  }
}
