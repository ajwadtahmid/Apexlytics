import 'dart:math' show min;
import '../../models/map_rotation.dart';

// Small grace period added to a rotation's remaining time before refetching,
// so the server has actually flipped the rotation by the time we ask for it
// (avoids racing the boundary and pulling the same, not-yet-rotated data).
const kRotationFlipBuffer = Duration(seconds: 15);

/// Never refetch the rotation sooner than this: the proxy caches /maprotation
/// for 30 s, and a rotation reporting no time left would otherwise be refetched
/// at round-trip speed until the rate limit answered 429.
const kMinRotationRefresh = Duration(seconds: 30);

/// How long to wait before refetching [rotation]: the soonest end among the
/// watched modes (the `notify*` flags), or null when none gives a time to wait
/// for. A mode whose block upstream left out (no map, no time) is skipped, not
/// read as "ended now".
Duration? rotationRefreshDelay(
  MapRotation rotation, {
  required bool notifyRanked,
  required bool notifyPubs,
  required bool notifyMixtape,
  required bool notifyWildcard,
}) {
  final watched = <MapMode?>[
    if (notifyRanked) rotation.rankedCurrent,
    if (notifyPubs) rotation.battleRoyaleCurrent,
    if (notifyMixtape) rotation.ltmCurrent,
    if (notifyWildcard) rotation.wildcardCurrent,
  ];
  final remaining = [
    for (final mode in watched)
      if (mode != null && (mode.remainingSecs > 0 || mode.map != 'Unknown'))
        mode.remainingSecs,
  ];
  if (remaining.isEmpty) return null;

  final delay = Duration(seconds: remaining.reduce(min)) + kRotationFlipBuffer;
  return delay < kMinRotationRefresh ? kMinRotationRefresh : delay;
}

int calculateMinActiveNotificationInterval({
  required bool notifyRanked,
  required int rankedMinutes,
  required bool notifyPubs,
  required int pubsMinutes,
  required bool notifyMixtape,
  required int mixtapeMinutes,
  required bool notifyWildcard,
  required int wildcardMinutes,
}) {
  final active = [
    if (notifyRanked && rankedMinutes > 0) rankedMinutes,
    if (notifyPubs && pubsMinutes > 0) pubsMinutes,
    if (notifyMixtape && mixtapeMinutes > 0) mixtapeMinutes,
    if (notifyWildcard && wildcardMinutes > 0) wildcardMinutes,
  ];
  return active.isEmpty ? 0 : active.reduce(min);
}
