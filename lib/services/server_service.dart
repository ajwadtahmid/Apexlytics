import '../models/server_status.dart';
import 'api_service.dart';
import '../constants/api_constants.dart';

class ServerService {
  final ApiService _api;
  ServerService(this._api);

  Future<ApiResult<ServerStatus>> getServerStatus() async {
    final result = await _api.get(ApiConstants.serversPath);
    return ApiResult(
      ServerStatus.fromJson(result.data),
      staleAt: result.staleAt,
    );
  }
}
