import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/server_status.dart';
import '../services/api_service.dart';
import 'api_provider.dart';

final serverStatusProvider = FutureProvider<ApiResult<ServerStatus>>(
  (ref) => ref.watch(serverServiceProvider).getServerStatus(),
);
