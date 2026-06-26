import '../constants/api_constants.dart';
import '../models/ranked_match.dart';
import 'api_service.dart';

/// Fetches ranked match history from the gated `/games` endpoint.
///
/// The endpoint is restricted to approved UIDs server-side; an unapproved UID
/// yields a `403` that surfaces here as an [AppException]. The backend keeps the
/// cache warm via its own cron, so the app only ever *reads* — never polls
/// `/bridge` itself.
class GamesService {
  final ApiService _api;
  GamesService(this._api);

  Future<List<RankedMatch>> getMatches(String uid) async {
    // Live match history — always fetch fresh; the backend cron is the cache.
    final result = await _api.getList(
      ApiConstants.gamesPath,
      params: {'uid': uid, 'limit': ApiConstants.gamesHistoryLimit},
      noCache: true,
    );
    return RankedMatch.listFromJson(result.data);
  }
}
