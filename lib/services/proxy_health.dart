import 'package:dio/dio.dart';

/// How one proxy answered a health check.
enum ProxyState { online, slow, down, notConfigured }

typedef ProxyHealth = ({ProxyState state, Duration? latency});

/// Slower than this still counts as working, but is shown as slow.
const Duration kProxySlowAfter = Duration(seconds: 1);

/// Longest a check waits. A sleeping free-tier host can take longer to wake,
/// and is then reported as not responding.
const Duration kProxyCheckTimeout = Duration(seconds: 10);

/// Asks the proxy at [baseUrl] whether it is up. `/healthz` is public, so no
/// client token is sent. An empty [baseUrl] is [ProxyState.notConfigured].
Future<ProxyHealth> checkProxy(String baseUrl, {Dio? dio}) async {
  if (baseUrl.isEmpty) return (state: ProxyState.notConfigured, latency: null);
  final client =
      dio ??
      Dio(
        BaseOptions(
          connectTimeout: kProxyCheckTimeout,
          receiveTimeout: kProxyCheckTimeout,
        ),
      );
  final clock = Stopwatch()..start();
  try {
    final res = await client.get<Object?>(
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/healthz',
      options: Options(validateStatus: (_) => true),
    );
    clock.stop();
    final ok = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
    if (!ok) return (state: ProxyState.down, latency: null);
    return (
      state: clock.elapsed >= kProxySlowAfter
          ? ProxyState.slow
          : ProxyState.online,
      latency: clock.elapsed,
    );
  } on DioException {
    return (state: ProxyState.down, latency: null);
  }
}
