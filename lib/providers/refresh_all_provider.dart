import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/games_service.dart';
import '../services/player_service.dart';
import '../utils/app_logger.dart';
import '../utils/storage/legend_stats_storage.dart';
import '../utils/storage/ranked_history_store.dart';
import '../utils/storage/rp_snapshot_storage.dart';
import '../utils/storage/season_storage.dart';
import 'api_provider.dart';
import 'owner_provider.dart';
import 'ranked_provider.dart';
import 'settings_provider.dart';

/// How refreshing one profile went; stats and history succeed or fail independently.
class ProfileRefreshResult {
  final PlayerProfile profile;

  /// Fresh stats were fetched and recorded (false on failure or a stale cached copy).
  final bool statsOk;

  /// What the history sync decided; null when the call itself failed.
  final RankedSyncOutcome? history;

  /// Matches the sync added to the local history.
  final int newMatches;

  const ProfileRefreshResult({
    required this.profile,
    required this.statsOk,
    required this.history,
    required this.newMatches,
  });

  bool get historyOk => history == RankedSyncOutcome.synced;

  /// Whether anything needs a second look.
  bool get hasProblem => !statsOk || !historyOk;

  String get statsSummary =>
      statsOk ? 'Stats updated' : "Couldn't update stats";

  String get historySummary => switch (history) {
    RankedSyncOutcome.synced =>
      newMatches > 0
          ? '+$newMatches new ${newMatches == 1 ? 'match' : 'matches'}'
          : 'History up to date',
    RankedSyncOutcome.queued => 'History queued — try again later',
    RankedSyncOutcome.busy => 'Server busy — try again in a minute',
    RankedSyncOutcome.notTracked => 'Not tracked yet, so no history to fetch',
    _ => "Couldn't fetch history",
  };
}

class RefreshAllReport {
  final List<ProfileRefreshResult> results;

  /// A ranked season was learned; callers should refresh the season list.
  final bool seasonsChanged;

  /// "Clear all data" ran mid-way, so the run stopped; [results] is what finished.
  final bool aborted;

  const RefreshAllReport({
    required this.results,
    required this.seasonsChanged,
    required this.aborted,
  });

  int get newMatches => results.fold(0, (sum, r) => sum + r.newMatches);
  bool get hasProblems => results.any((r) => r.hasProblem);
}

/// Refreshes each profile in [profiles], one at a time, in order: stats (`/player/uid` → season
/// list, RP snapshot, legend stats) then history (`/games`, forced past the client cooldown).
/// One failing never stops the rest, and each part is reported separately.
///
/// Sequential because the server paces upstream calls and owner priority goes to the earliest
/// profiles. Stops without further writes if "Clear all data" runs meanwhile.
Future<RefreshAllReport> refreshProfiles({
  required List<PlayerProfile> profiles,
  required PlayerService players,
  required GamesService games,
  required RankedHistoryStore store,
  required SharedPreferences prefs,
  void Function(int done, int total)? onProgress,
}) async {
  final epoch = store.dataEpoch;
  bool cleared() => store.dataEpoch != epoch;

  final results = <ProfileRefreshResult>[];
  var seasonsChanged = false;
  var aborted = false;

  for (var i = 0; i < profiles.length; i++) {
    if (cleared()) {
      aborted = true;
      break;
    }
    final profile = profiles[i];

    var statsOk = false;
    try {
      final fetched = await players.getPlayerStatsByUid(
        profile.uid,
        profile.platform,
      );
      if (cleared()) {
        aborted = true;
        break;
      }
      // A stale copy isn't a new reading.
      if (fetched.staleAt == null) {
        final stats = fetched.data;
        final season = stats.rankedSeason;
        if (season != null && await upsertSeason(season, prefs)) {
          seasonsChanged = true;
        }
        await appendSnapshot(stats, store, uid: profile.uid);
        await mergeLegendStats(stats.legendStats, prefs, uid: profile.uid);
        statsOk = true;
      }
    } catch (e) {
      // The type only: the text of a storage error can carry a UID.
      log.w('Refresh all: stats failed (${e.runtimeType})');
    }
    if (cleared()) {
      aborted = true;
      break;
    }

    RankedSyncOutcome? outcome;
    var added = 0;
    try {
      final before = await store.count(profile.uid);
      outcome = await syncRankedHistory(
        uid: profile.uid,
        store: store,
        prefs: prefs,
        games: () => games,
        // Read now: the stats step may have just learned the current season.
        seasons: loadAllSeasonsSync(prefs),
        force: true,
      );
      added = (await store.count(profile.uid) - before).clamp(0, 1 << 30);
    } catch (e) {
      log.w('Refresh all: history failed (${e.runtimeType})');
    }

    results.add(
      ProfileRefreshResult(
        profile: profile,
        statsOk: statsOk,
        history: outcome,
        newMatches: added,
      ),
    );
    onProgress?.call(i + 1, profiles.length);
  }

  return RefreshAllReport(
    results: results,
    seasonsChanged: seasonsChanged,
    aborted: aborted,
  );
}

class RefreshAllState {
  final bool running;
  final int done;
  final int total;
  const RefreshAllState({this.running = false, this.done = 0, this.total = 0});
}

final refreshAllProvider =
    NotifierProvider<RefreshAllNotifier, RefreshAllState>(
      RefreshAllNotifier.new,
    );

/// Owner-only "Refresh all profiles".
class RefreshAllNotifier extends Notifier<RefreshAllState> {
  @override
  RefreshAllState build() => const RefreshAllState();

  /// Refreshes every saved profile, active first. Null if nothing ran (already running, not an
  /// owner device, or no profiles). Callers refresh what's on screen from the report.
  Future<RefreshAllReport?> run() async {
    if (state.running || !ref.read(ownerUnlockedProvider)) return null;

    final settings = ref.read(playerSettingsProvider);
    final active = settings.activeProfile;
    final profiles = [
      ?(active != null && active.isSet ? active : null),
      for (final p in settings.profiles)
        if (p.isSet && p != active) p,
    ];
    if (profiles.isEmpty) return null;

    state = RefreshAllState(running: true, total: profiles.length);
    try {
      return await refreshProfiles(
        profiles: profiles,
        players: ref.read(playerServiceProvider),
        games: ref.read(gamesServiceProvider),
        store: ref.read(rankedHistoryStoreProvider),
        prefs: ref.read(sharedPreferencesProvider),
        onProgress: (done, total) {
          if (ref.mounted) {
            state = RefreshAllState(running: true, done: done, total: total);
          }
        },
      );
    } finally {
      if (ref.mounted) state = const RefreshAllState();
    }
  }
}
