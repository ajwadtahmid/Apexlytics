import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env/env.dart';
import '../services/proxy_health.dart';

/// How a proxy is checked; replaced in tests.
final proxyCheckerProvider = Provider<Future<ProxyHealth> Function(String url)>(
  (ref) => checkProxy,
);

typedef ProxyHealthReport = ({ProxyHealth primary, ProxyHealth backup});

/// Checks both proxies at once. Runs when the Server Status page opens and
/// not again until it is reopened.
final proxyHealthProvider = FutureProvider.autoDispose<ProxyHealthReport>((
  ref,
) async {
  final check = ref.watch(proxyCheckerProvider);
  final results = await Future.wait([
    check(Env.proxyUrl),
    check(Env.proxyUrlBackup),
  ]);
  return (primary: results[0], backup: results[1]);
});
