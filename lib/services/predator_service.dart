import '../models/predator.dart';
import 'api_service.dart';
import '../constants/api_constants.dart';

class PredatorService {
  final ApiService _api;
  PredatorService(this._api);

  Future<ApiResult<PredatorResponse>> getPredator() async {
    final result = await _api.get(ApiConstants.predatorPath);
    return ApiResult(
      PredatorResponse.fromJson(result.data),
      staleAt: result.staleAt,
    );
  }
}
