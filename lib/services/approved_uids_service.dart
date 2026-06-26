import '../constants/api_constants.dart';
import 'api_service.dart';

/// Fetches the server-side allowlist of UIDs permitted to view the ranked
/// breakdown. The payload is `[{ "uid": "...", "platform": "..." }, ...]` with
/// no display name — names come from `/games` or already-loaded player stats.
class ApprovedUidsService {
  final ApiService _api;
  ApprovedUidsService(this._api);

  Future<Set<String>> getApprovedUids() async {
    final result = await _api.getList(ApiConstants.approvedUidsPath);
    final uids = <String>{};
    for (final e in result.data) {
      if (e is Map<String, dynamic>) {
        final uid = e['uid']?.toString();
        if (uid != null && uid.isNotEmpty) uids.add(uid);
      }
    }
    return uids;
  }
}
