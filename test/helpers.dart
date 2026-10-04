import 'dart:convert';
import 'dart:typed_data';

import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:dio/dio.dart';

/// Builds a minimal [PlayerStats] for use in tests. Override only the fields
/// you care about; everything else gets a sensible default.
PlayerStats buildStats({
  String name = 'TestPlayer',
  String uid = 'uid123',
  int rankScore = 1000,
  String rank = 'Gold',
  String platform = 'PC',
  bool isOnline = false,
  bool isInGame = false,
  List<LegendStat>? legendStats,
  SeasonMeta? rankedSeason,
}) {
  return PlayerStats(
    rankedSeason: rankedSeason,
    name: name,
    uid: uid,
    level: 100,
    rank: rank,
    rankScore: rankScore,
    platform: platform,
    currentLegend: 'Wraith',
    isOnline: isOnline,
    isInGame: isInGame,
    trackers: [],
    legendStats: legendStats ?? [],
  );
}

/// Builds a [LegendTracker] for use in tests.
LegendTracker buildTracker({
  String key = 'kills',
  String? displayName,
  int value = 100,
}) {
  return LegendTracker(key: key, displayName: displayName ?? key, value: value);
}

/// Builds a [LegendStat] for use in tests.
LegendStat buildLegend({
  String name = 'Wraith',
  List<LegendTracker>? trackers,
}) {
  return LegendStat(name: name, trackers: trackers ?? [buildTracker()]);
}

/// A scripted reply: a status and a JSON-encodable body.
class FakeReply {
  final int status;
  final Object? body;
  const FakeReply(this.status, [this.body]);
}

/// A stand-in for the network for tests that build a real `ApiService`. Replaces only the
/// transport, so interceptors and error mapping still run but nothing leaves the process.
///
/// A path with no route in [routes] answers 404 (the proxy's error body), visible in [requests].
/// A route maps a path to a JSON-encodable body, a [FakeReply] for a non-200 status, or a
/// function of the request returning either (to answer per query parameter).
class FakeHttpAdapter implements HttpClientAdapter {
  final Map<String, Object?> routes;

  /// Every request the app made, in order.
  final List<RequestOptions> requests = [];

  FakeHttpAdapter([this.routes = const {}]);

  /// Paths requested so far, in order.
  List<String> get paths => [for (final r in requests) r.path];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final routed = routes.containsKey(options.path);
    var reply = routed ? routes[options.path] : null;
    if (reply is Object? Function(RequestOptions)) reply = reply(options);
    final FakeReply answer = reply is FakeReply
        ? reply
        : routed
        ? FakeReply(200, reply)
        : const FakeReply(404, {'error': 'Not found'});
    return ResponseBody.fromString(
      jsonEncode(answer.body),
      answer.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
