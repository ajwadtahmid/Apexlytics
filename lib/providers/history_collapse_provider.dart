import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which history day headers are collapsed, keyed by [historyDayKey]. Held in
/// memory only, so a day stays collapsed while the app is open — across tab
/// switches and screen changes — and everything is expanded again on restart.
final collapsedHistoryDaysProvider =
    NotifierProvider<CollapsedHistoryDays, Set<String>>(
      CollapsedHistoryDays.new,
    );

class CollapsedHistoryDays extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String key) {
    state = state.contains(key)
        ? ({...state}..remove(key))
        : {...state, key};
  }
}

/// Key for [day] within [scope] (the History tab, or one legend/map page), so
/// collapsing a day in one list doesn't collapse it in another.
String historyDayKey(String scope, DateTime day) =>
    '$scope|${day.year}-${day.month}-${day.day}';
