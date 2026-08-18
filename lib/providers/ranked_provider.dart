import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../constants/prefs_keys.dart';
import '../models/ranked_match.dart';
import '../models/season_meta.dart';
import '../services/games_service.dart';
import '../utils/app_logger.dart';
import '../utils/ranked/ranked_aggregates.dart';
import '../utils/ranked/ranked_period.dart';
import '../utils/storage/ranked_history_store.dart';
import '../utils/storage/season_storage.dart';
import 'api_provider.dart';
import 'settings_provider.dart';

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

/// Why the ranked view is showing what it's showing — the breakdown is always
/// served from the local store, and this explains how current that store is.
enum RankedSyncOutcome {
  /// Fresh match data was merged from `/games`.
  synced,

  /// Skipped the network: the last sync is still inside the cooldown.
  cooldown,

  /// The server has no slot free right now. Purely a delay.
  queued,

  /// Nobody is polling this UID upstream, so no history is being recorded.
  /// The only state that needs the user to *do* something.
  notTracked,

  /// The request failed, but persisted history is available to show.
  offline,
}

/// Backoff after a failure when there's still history to display. Short, because
/// this is a transient network problem rather than a budget decision.
const _kOfflineRetry = Duration(minutes: 5);

/// Syncs ranked history for [uid]: fetches the latest 100 from `/games`, merges
/// them into the local store, and classifies any newly/legacy-unstamped rows.
/// This is the write half — the split picker and per-split match loaders below
/// depend on it so they re-run after each sync, but it deliberately loads *no*
/// matches into memory itself.
///
/// Requests are rate-limited per UID against a persisted deadline. A `202`
/// response sets the deadline from the server's own `Retry-After`.
///
/// A fetch failure is swallowed when persisted history exists (graceful
/// offline/stale) and only rethrown when there's nothing to show, so the view
/// can surface a retry.
final rankedSyncProvider = FutureProvider.autoDispose
    .family<RankedSyncOutcome, String>((ref, uid) async {
      final store = ref.watch(rankedHistoryStoreProvider);
      final seasons = ref.watch(rankedSeasonsProvider);
      final prefs = ref.watch(sharedPreferencesProvider);

      Future<RankedSyncOutcome> remember(
        RankedSyncOutcome outcome,
        Duration wait,
      ) async {
        await prefs.setInt(
          PrefsKeys.gamesNextSync(uid),
          DateTime.now().add(wait).millisecondsSinceEpoch,
        );
        await prefs.setString(PrefsKeys.gamesLastOutcome(uid), outcome.name);
        return outcome;
      }

      final nextSyncAt = prefs.getInt(PrefsKeys.gamesNextSync(uid)) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch < nextSyncAt) {
        // Inside the backoff window: replay the outcome the last real fetch
        // recorded, falling back to a plain cooldown when nothing is stored.
        final last = prefs.getString(PrefsKeys.gamesLastOutcome(uid));
        return RankedSyncOutcome.values.firstWhere(
          (o) => o.name == last,
          orElse: () => RankedSyncOutcome.cooldown,
        );
      }

      try {
        final result = await ref.watch(gamesServiceProvider).getMatches(uid);
        switch (result) {
          case GamesPending(:final retryAfter, :final isNotTracked):
            return await remember(
              isNotTracked
                  ? RankedSyncOutcome.notTracked
                  : RankedSyncOutcome.queued,
              retryAfter,
            );
          case GamesMatches(:final matches):
            // An empty list is a valid answer — tracking is live, nothing recorded
            // yet — so it still counts as a successful sync.
            await store.upsertAll(uid, matches, seasons: seasons);
            await remember(
              RankedSyncOutcome.synced,
              ApiConstants.gamesSyncCooldown,
            );
        }
      } catch (e) {
        if (await store.count(uid) == 0) rethrow;
        log.w('games fetch failed; serving persisted history', error: e);
        return remember(RankedSyncOutcome.offline, _kOfflineRetry);
      }
      // Re-read from prefs rather than reusing the watched `seasons` above: other
      // screens (e.g. the stats tab) call upsertSeason() directly against prefs
      // without going through this provider, so a season learned there during
      // the same session wouldn't otherwise be reflected here until relaunch.
      final latestSeasons = loadAllSeasonsSync(
        ref.read(sharedPreferencesProvider),
      );
      await store.backfillSeasonIds(latestSeasons);
      // Drain the kills/damage backlog left by the v2 → v3 column migration.
      await store.backfillKillsDamage();
      return RankedSyncOutcome.synced;
    });

/// Whether the backend is currently seeing polls for [uid] — that is, whether
/// history is actually accruing right now. Backed by our own `/player` traffic,
/// so it costs no `/games` budget slot. Null on failure.
final gamesEligibilityProvider = FutureProvider.autoDispose
    .family<GamesEligibility?, String>((ref, uid) async {
      if (uid.isEmpty) return null;
      try {
        return await ref.watch(gamesServiceProvider).getEligibility(uid);
      } catch (e) {
        log.d('Eligibility check failed', error: e);
        return null;
      }
    });

/// Net ranked RP for [uid] over a window, via [RankedHistoryStore.netRpInWindow].
///
/// Null means "fall back to the RP snapshots": not the active profile, sync
/// failed with nothing persisted, or history has a hole. Never throws.
/// `currentRp` is part of the cache key — [RankedHistoryStore.netRpInWindow]'s
/// completeness check validates against it.
///
/// Restricted to the *active profile* rather than any UID, even though this
/// provider is also rendered for search results — history only accrues for
/// players actively being polled.
final weeklyNetRpProvider = FutureProvider.autoDispose
    .family<int?, ({String uid, DateTime start, DateTime end, int currentRp})>((
      ref,
      arg,
    ) async {
      if (arg.uid.isEmpty) return null;
      final activeUid = ref.watch(playerSettingsProvider.select((s) => s.uid));
      if (arg.uid != activeUid) return null;
      try {
        await ref.watch(rankedSyncProvider(arg.uid).future);
        return await ref
            .watch(rankedHistoryStoreProvider)
            .netRpInWindow(
              arg.uid,
              arg.start,
              arg.end,
              currentRp: arg.currentRp,
            );
      } catch (e) {
        log.d('Weekly net RP unavailable; using RP snapshots', error: e);
        return null;
      }
    });

/// The split buckets that drive the picker for [uid], built from a cheap ranked
/// `COUNT` per split — no match hydration. Re-runs after each [rankedSyncProvider].
final rankedSplitsProvider = FutureProvider.autoDispose
    .family<List<RankedSplitBucket>, String>((ref, uid) async {
      await ref.watch(rankedSyncProvider(uid).future);
      final store = ref.watch(rankedHistoryStoreProvider);
      final seasons = ref.watch(rankedSeasonsProvider);
      final counts = await store.rankedSeasonCounts(uid);
      return buildSplitBuckets(counts, seasons);
    });

/// Loads just one split's matches (pubs included), keyed by uid + split id, so
/// only the selected split is ever held in memory — never the whole history.
/// Re-runs after each [rankedSyncProvider].
final rankedSplitMatchesProvider = FutureProvider.autoDispose
    .family<List<RankedMatch>, ({String uid, String splitId})>((
      ref,
      arg,
    ) async {
      await ref.watch(rankedSyncProvider(arg.uid).future);
      final store = ref.watch(rankedHistoryStoreProvider);
      return store.getBySeason(arg.uid, arg.splitId);
    });

/// The resolved view for one split plus its overview aggregates, computed once
/// per (matches × selected week) rather than on every widget rebuild. The
/// aggregates are O(matches), so recomputing them in `build()` — which the
/// 10-min refresh timer, tab switches and ancestor rebuilds all trigger — was
/// wasted work; caching them here means they only recompute when the loaded
/// matches or the week selection actually change.
typedef RankedSplitView = ({
  RankedView view,
  RankedSummary summary,
  List<LegendBreakdown> legends,
  List<MapBreakdown> maps,
});

final rankedSplitViewProvider = FutureProvider.autoDispose
    .family<RankedSplitView, ({String uid, String splitId})>((ref, arg) async {
      final splits = await ref.watch(rankedSplitsProvider(arg.uid).future);
      final matches = await ref.watch(rankedSplitMatchesProvider(arg).future);
      final weekIndex = ref.watch(
        rankedPeriodProvider.select((p) => p.weekIndex),
      );
      final view = resolveRankedView(
        splits: splits,
        splitMatches: matches,
        selectedSplitId: arg.splitId,
        weekIndex: weekIndex,
      );
      final filtered = view.filtered;
      return (
        view: view,
        summary: summarize(filtered),
        legends: legendBreakdowns(filtered),
        maps: mapBreakdowns(filtered),
      );
    });

/// The Lifetime (all-splits) aggregates. Summary/legends/maps are pure SQL
/// `GROUP BY` sums — no matches hydrated regardless of history size. Time-of-day
/// can't be grouped in SQL without risking wrong local-hour/DST bucketing, so it
/// hydrates a narrow two-column (start time + RP) projection instead — the only
/// part that scales with match count. Feeds the Lifetime Overview / Legends /
/// Maps tabs. Re-runs after each [rankedSyncProvider].
typedef RankedLifetimeAggregates = ({
  RankedSummary summary,
  List<LegendBreakdown> legends,
  List<MapBreakdown> maps,
  List<HourBucket> timeOfDay,
});

final rankedLifetimeAggregatesProvider = FutureProvider.autoDispose
    .family<RankedLifetimeAggregates, String>((ref, uid) async {
      await ref.watch(rankedSyncProvider(uid).future);
      final store = ref.watch(rankedHistoryStoreProvider);
      return (
        summary: await store.summaryFor(uid),
        legends: await store.legendBreakdownsFor(uid),
        maps: await store.mapBreakdownsFor(uid),
        timeOfDay: await store.timeOfDayBucketsFor(uid),
      );
    });
