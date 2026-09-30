import '../constants/api_constants.dart';
import '../models/ranked_match.dart';
import '../utils/error_messages.dart';
import 'api_service.dart';

/// The result of a `/games` fetch. `200` carries match data; `202` means the
/// request was accepted but there is nothing fresh to give — either the hourly
/// budget is exhausted or upstream isn't recording this player yet. Neither is
/// an error, and neither should be shown as "0 matches".
sealed class GamesResult {
  const GamesResult();
}

/// Fresh match history from upstream.
///
/// An empty [matches] list is a valid answer, not a failure: it means tracking
/// is active but no matches have been recorded in the window yet.
class GamesMatches extends GamesResult {
  final List<RankedMatch> matches;
  const GamesMatches(this.matches);
}

/// The server accepted the request but has no fresh data (HTTP `202`).
class GamesPending extends GamesResult {
  /// `queued` — waiting for a slot in the hourly budget.
  /// `not_tracked` — nobody is polling this UID, so nothing is being recorded.
  final String status;

  /// How long the server asked us to wait before trying again.
  final Duration retryAfter;

  const GamesPending({required this.status, required this.retryAfter});

  /// True when no history is accruing at all — the user has to keep the app
  /// (or an apexlegendsstatus.com tab) open before there is anything to fetch.
  bool get isNotTracked => status == 'not_tracked';
}

/// Whether upstream is currently recording match history for a UID.
typedef GamesEligibility = ({bool eligible, int? lastPolledAt, int pollCount});

/// Live `/games` hourly budget snapshot (see `/games/capacity` server-side).
/// [windowResetsAt] is when the oldest claimed slot frees up, not a fixed
/// clock time. [locked] means the server paused the whole budget after a
/// real upstream 429 — worth telling the user, distinct from "just busy".
typedef GamesCapacity = ({
  int maxPerHour,
  int used,
  int free,
  DateTime windowResetsAt,
  int waitlistDepth,
  bool locked,
});

/// Reads ranked match history from the budgeted `/games` endpoint.
///
/// `/games` is open to every UID, but upstream only allows a small,
/// server-configured number of unique players per hour (see
/// `/games/capacity` for the live figure), so the backend rations access
/// and answers `202` when it can't serve. Match data only accrues while a
/// player is being polled, which is what the app's stats-refresh timer
/// does — history is therefore forward-only.
class GamesService {
  final ApiService _api;
  GamesService(this._api);

  Future<GamesResult> getMatches(String uid) async {
    // Live match history — always ask; the backend owns the caching and the
    // per-UID cooldown, so there is nothing useful for the HTTP cache to do.
    final response = await _api.getWithStatus(
      ApiConstants.gamesPath,
      params: {'uid': uid, 'limit': ApiConstants.gamesHistoryLimit},
      // The backup has its own budget and tracking state, so re-running a
      // possibly-served request there can spend a second slot or report
      // "not tracked". A failure just shows stored history until the retry.
      failover: false,
    );

    if (response.status == 200) {
      // Only a list body is a valid 200. Anything else raises, sending the
      // caller down the failure path — persisted history plus a retry — rather
      // than the pending path below.
      if (response.data is! List) {
        throw const AppException(
          'Unexpected response from the history server.',
        );
      }
      return GamesMatches(RankedMatch.listFromJson(response.data as List));
    }

    if (response.status == 202) {
      final body = response.data is Map ? response.data as Map : const {};
      return GamesPending(
        status: body['status']?.toString() ?? 'queued',
        // Defaults to 5 minutes if the server didn't send a retry hint.
        retryAfter: Duration(
          seconds: (body['retryAfterSeconds'] as num?)?.toInt() ?? 300,
        ),
      );
    }

    // Anything else (a captive portal, a CDN error page, an intermediary
    // proxy) is a real failure, not "please wait" — treating every non-200
    // as pending used to report this as `queued`, wrongly telling the user
    // nothing is lost.
    throw AppException(
      'Unexpected response from the history server (${response.status}).',
      status: response.status,
    );
  }

  /// Checks whether history is currently accruing for [uid], without spending
  /// a `/games` request.
  Future<GamesEligibility> getEligibility(String uid) async {
    final response = await _api.getWithStatus(
      ApiConstants.gamesEligibilityPath,
      params: {'uid': uid},
    );
    final body = response.data is Map ? response.data as Map : const {};
    return (
      eligible: body['eligible'] == true,
      lastPolledAt: (body['lastPolledAt'] as num?)?.toInt(),
      pollCount: (body['pollCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Live hourly `/games` budget state — free slots and whether the window
  /// is locked. Costs no `/games` budget slot itself. Backs the "queued"
  /// empty state with something concrete instead of "please wait". Null on
  /// any non-200 response — a nice-to-have, so a failure just degrades to
  /// generic copy.
  Future<GamesCapacity?> getCapacity() async {
    final response = await _api.getWithStatus(ApiConstants.gamesCapacityPath);
    if (response.status != 200 || response.data is! Map) return null;
    final body = response.data as Map;
    final resetsAtMs = (body['windowResetsAt'] as num?)?.toInt();
    return (
      maxPerHour: (body['maxPerHour'] as num?)?.toInt() ?? 0,
      used: (body['used'] as num?)?.toInt() ?? 0,
      free: (body['free'] as num?)?.toInt() ?? 0,
      windowResetsAt: resetsAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(resetsAtMs)
          : DateTime.now(),
      waitlistDepth: (body['waitlistDepth'] as num?)?.toInt() ?? 0,
      locked: body['locked'] == true,
    );
  }
}
