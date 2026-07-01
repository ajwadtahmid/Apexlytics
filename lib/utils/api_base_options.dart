import 'package:dio/dio.dart';
import '../constants/timeout_constants.dart';
import '../env/env.dart';

/// Base Dio options (base URL, timeouts, client-token header) shared by the
/// foreground [ApiService] and the headless background-fetch isolate, which
/// can't reach the provider tree and so builds its own [Dio] client.
BaseOptions buildApiBaseOptions() {
  final clientToken = Env.clientToken;
  return BaseOptions(
    baseUrl: Env.proxyUrl,
    connectTimeout: TimeoutConstants.apiConnect,
    receiveTimeout: TimeoutConstants.apiReceive,
    headers: clientToken.isNotEmpty ? {'x-client-token': clientToken} : {},
  );
}
