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
import 'player_provider.dart';
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

      // Scoped to just the network call. A local write failure
      // (store.upsertAll, backfillSeasonIds, a prefs write) used to be
      // caught by the same handler and misreported as `offline`, which is
      // specifically the wrong diagnosis for the class of failure
      // that most needs an accurate one. Only a fetch failure gets the
      // graceful "serve persisted history" treatment; a write failure now
      // propagates as a real error.
      final GamesResult result;
      try {
        result = await ref.watch(gamesServiceProvider).getMatches(uid);
      } catch (e) {
        if (await store.count(uid) == 0) rethrow;
        log.w('games fetch failed; serving persisted history', error: e);
        return remember(RankedSyncOutcome.offline, _kOfflineRetry);
      }
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
      }
      // Re-read from prefs rather than reusing the watched `seasons` above: other
      // screens (e.g. the stats tab) call upsertSeason() directly against prefs
      // without going through this provider, so a season learned there during
      // the same session wouldn't otherwise be reflected here until relaunch.
      final latestSeasons = loadAllSeasonsSync(
        ref.read(sharedPreferencesProvider),
      );
      await store.backfillSeasonIds(latestSeasons);
      // Committed only after backfillSeasonIds succeeds, so a write failure
      // there can't get recorded as a successful sync and lock the user out
      // of retrying for 6 h.
      return remember(RankedSyncOutcome.synced, ApiConstants.gamesSyncCooldown);
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
  // Belongs here, not in build - these were computed inline in
  // _OverviewTab and re-ran on every rebuild, the exact waste this provider
  // exists to avoid.
  List<HourBucket> timeOfDay,
  List<WeekdayBucket> dayOfWeek,
  RankedSummary fullSquad,
  RankedSummary partialSquad,
  // Also belongs here, not in build - RankedRpChart and
  // RankedSquadSessionsEntry used to each call sessionize() on every
  // rebuild of the always-visible Overview tab.
  List<RankedSession> sessions,
  // Per-legend/per-map trend lines, keyed by canonical legend name / map key.
  // Computed once here rather than per rebuild in the widget layer.
  Map<String, EntityTrends> legendTrends,
  Map<String, EntityTrends> mapTrends,
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
        timeOfDay: timeOfDayBuckets(filtered),
        dayOfWeek: dayOfWeekBuckets(filtered),
        fullSquad: summarize(filtered.where((m) => m.isPartyFull).toList()),
        partialSquad: summarize(filtered.where((m) => !m.isPartyFull).toList()),
        sessions: sessionize(filtered),
        legendTrends: legendTrendsByEntity(filtered),
        mapTrends: mapTrendsByEntity(filtered),
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
  List<WeekdayBucket> dayOfWeek,
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
        dayOfWeek: await store.dayOfWeekBucketsFor(uid),
      );
    });

/// Lifetime-scope Personal Best: the three standout single-game records (RP,
/// kills, damage) via [RankedHistoryStore.personalBestGamesFor]'s SQL
/// queries — cheap regardless of history size, unlike full match hydration.
final rankedPersonalBestProvider = FutureProvider.autoDispose
    .family<PersonalBestGames, String>((ref, uid) async {
      await ref.watch(rankedSyncProvider(uid).future);
      final store = ref.watch(rankedHistoryStoreProvider);
      return store.personalBestGamesFor(uid);
    });

/// Every aggregate the split-comparison tab needs for one split, bundled the
/// same way [RankedLifetimeAggregates] bundles Lifetime's — all SQL, no match
/// hydration, so comparing two arbitrary splits costs the same regardless of
/// which two are picked (neither has to be the split currently open).
typedef RankedSplitDetail = ({
  RankedSummary summary,
  List<LegendBreakdown> legends,
  List<MapBreakdown> maps,
  List<LegendMapCell> legendMap,
  ({RankedSummary full, RankedSummary partial}) squadBreakdown,
  List<HourBucket> timeOfDay,
  List<WeekdayBucket> dayOfWeek,
});

final rankedSplitDetailProvider = FutureProvider.autoDispose
    .family<RankedSplitDetail, ({String uid, String splitId})>((
      ref,
      arg,
    ) async {
      await ref.watch(rankedSyncProvider(arg.uid).future);
      final store = ref.watch(rankedHistoryStoreProvider);
      return (
        summary: await store.summaryFor(arg.uid, seasonId: arg.splitId),
        legends: await store.legendBreakdownsFor(
          arg.uid,
          seasonId: arg.splitId,
        ),
        maps: await store.mapBreakdownsFor(arg.uid, seasonId: arg.splitId),
        legendMap: await store.legendMapBreakdownsFor(
          arg.uid,
          seasonId: arg.splitId,
        ),
        squadBreakdown: await store.squadBreakdownFor(
          arg.uid,
          seasonId: arg.splitId,
        ),
        timeOfDay: await store.timeOfDayBucketsFor(
          arg.uid,
          seasonId: arg.splitId,
        ),
        dayOfWeek: await store.dayOfWeekBucketsFor(
          arg.uid,
          seasonId: arg.splitId,
        ),
      );
    });

/// Every provider whose value is derived from the local ranked store or the
/// active profile. Any destructive or restorative data action (clear all,
/// import backup) must invalidate all of them — add new derived providers
/// here, not at the call site.
///
/// Defined once, next to the providers it names, for the same reason
/// [PlayerSettingsNotifier.clearAll]'s survivors allowlist is defined next to
/// the keys it sweeps: a list maintained three files away from what it
/// describes rots the moment a provider is added and this isn't updated. The
/// `autoDispose` split/lifetime providers stay subscribed (and so keep
/// serving stale data) as long as the Stats tab's `IndexedStack` entry is
/// mounted, which a Settings-screen visit alone doesn't tear down.
void invalidatePlayerDerivedProviders(WidgetRef ref) {
  ref.invalidate(rankedSyncProvider);
  ref.invalidate(rankedSplitsProvider);
  ref.invalidate(rankedSplitMatchesProvider);
  ref.invalidate(rankedSplitViewProvider);
  ref.invalidate(rankedLifetimeAggregatesProvider);
  ref.invalidate(rankedPersonalBestProvider);
  ref.invalidate(rankedSplitDetailProvider);
  ref.invalidate(weeklyNetRpProvider);
  ref.invalidate(gamesEligibilityProvider);
  ref.invalidate(rankedSeasonsProvider);
  ref.invalidate(myPlayerStatsProvider);
  // Resets the split/week selection back to its build() default (newest
  // split, All weeks). Without this the previously-selected splitId can name
  // a bucket that no longer exists post-clear/import; effectiveSplitId
  // already falls back gracefully when that happens, but the picker
  // otherwise shows a stale selection until the user changes it themselves.
  ref.invalidate(rankedPeriodProvider);
}

/// Every provider whose value is derived from stored *match rows* — the set
/// a hand correction (see `match_edit_sheet.dart`) can change. Deliberately
/// excludes [rankedSyncProvider] and [rankedSplitsProvider], so saving an
/// edit never spends a `/games` request or touches the split picker (edited
/// fields don't change which split a match belongs to).
///
/// Defined here, next to the providers it names, for the same reason
/// [invalidatePlayerDerivedProviders] is — a list maintained at the call
/// site rots the moment a new store-derived provider is added.
void invalidateMatchDerivedProviders(WidgetRef ref) {
  ref.invalidate(rankedSplitMatchesProvider);
  ref.invalidate(rankedSplitViewProvider);
  ref.invalidate(rankedLifetimeAggregatesProvider);
  ref.invalidate(rankedSplitDetailProvider);
  ref.invalidate(rankedPersonalBestProvider);
  ref.invalidate(weeklyNetRpProvider);
}
