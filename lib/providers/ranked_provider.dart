import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/prefs_keys.dart';
import '../models/ranked_match.dart';
import '../models/season_meta.dart';
import '../utils/app_logger.dart';
import '../utils/storage/ranked_history_store.dart';
import '../utils/storage/season_storage.dart';
import 'api_provider.dart';
import 'settings_provider.dart';

/// The server-side allowlist of UIDs permitted to view the ranked breakdown.
///
/// Backed by a SharedPreferences cache so the gated tab can be decided
/// synchronously on launch (no pop-in after the first run). On every launch it
/// refreshes from the backend and re-validates periodically while the app runs;
/// network failures keep the last cached set.
final approvedUidsProvider =
    NotifierProvider<ApprovedUidsNotifier, Set<String>>(
  ApprovedUidsNotifier.new,
);

class ApprovedUidsNotifier extends Notifier<Set<String>> {
  static const _kRevalidateInterval = Duration(hours: 6);
  Timer? _timer;

  @override
  Set<String> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final cached = _readCache(prefs);

    // Refresh from the backend now, then re-validate periodically.
    Future.microtask(refresh);
    _timer = Timer.periodic(_kRevalidateInterval, (_) => refresh());
    ref.onDispose(() => _timer?.cancel());

    return cached;
  }

  /// Re-fetches the allowlist, updates the cache, and emits the new set.
  /// Keeps the existing cached set on failure.
  Future<void> refresh() async {
    try {
      final fresh = await ref.read(approvedUidsServiceProvider).getApprovedUids();
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(
        PrefsKeys.approvedUidsCache,
        jsonEncode(fresh.toList()),
      );
      if (!setEquals(fresh, state)) state = fresh;
    } catch (e) {
      log.d('Approved-UIDs refresh failed; keeping cache', error: e);
    }
  }

  Set<String> _readCache(SharedPreferences prefs) {
    final raw = prefs.getString(PrefsKeys.approvedUidsCache);
    if (raw == null) return <String>{};
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }
}

/// Whether [uid] may view the ranked breakdown. False for an empty UID.
final isUidApprovedProvider = Provider.family<bool, String>((ref, uid) {
  if (uid.isEmpty) return false;
  return ref.watch(approvedUidsProvider).contains(uid);
});

/// Whether the *active profile* is approved — drives the Ranked tab's presence.
final activeUidApprovedProvider = Provider<bool>((ref) {
  final uid = ref.watch(playerSettingsProvider.select((s) => s.uid));
  return ref.watch(isUidApprovedProvider(uid));
});

/// App-lifetime handle to the local ranked-history database.
final rankedHistoryStoreProvider = Provider<RankedHistoryStore>((ref) {
  final store = RankedHistoryStore();
  ref.onDispose(store.close);
  return store;
});

/// All season/splits the app has recorded — used to bucket matches by split.
final rankedSeasonsProvider = Provider<Map<String, SeasonMeta>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return loadAllSeasonsSync(prefs);
});

/// The selected split + week, shared across all Ranked sub-tabs. A null
/// [splitId] resolves to the current (newest) split; [weekIndex] -1 = All weeks.
class RankedPeriod {
  final String? splitId;
  final int weekIndex;
  const RankedPeriod({this.splitId, this.weekIndex = -1});
}

final rankedPeriodProvider =
    NotifierProvider<RankedPeriodNotifier, RankedPeriod>(
  RankedPeriodNotifier.new,
);

class RankedPeriodNotifier extends Notifier<RankedPeriod> {
  @override
  RankedPeriod build() => const RankedPeriod();

  /// Switching split resets the week scope to All.
  void selectSplit(String id) => state = RankedPeriod(splitId: id);

  void selectWeek(int index) =>
      state = RankedPeriod(splitId: state.splitId, weekIndex: index);
}

/// Ranked match history for [uid]: fetches the latest 100 from `/games`, merges
/// them into the local store, and returns the *full* persisted history (so
/// matches older than the API window remain viewable).
///
/// If the fetch fails but history exists, the persisted history is returned
/// (graceful offline/stale). Only when there's no fetch *and* no history does
/// the error surface so the view can show a retry.
final rankedMatchesProvider =
    FutureProvider.autoDispose.family<List<RankedMatch>, String>(
  (ref, uid) async {
    final store = ref.watch(rankedHistoryStoreProvider);
    try {
      final fresh = await ref.watch(gamesServiceProvider).getMatches(uid);
      await store.upsertAll(uid, fresh);
    } catch (e) {
      final existing = await store.getAll(uid);
      if (existing.isEmpty) rethrow;
      log.w('games fetch failed; serving persisted history', error: e);
      return existing;
    }
    return store.getAll(uid);
  },
);
