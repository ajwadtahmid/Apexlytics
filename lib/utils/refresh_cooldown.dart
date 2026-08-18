/// Silently throttles repeated manual refresh/retry actions per key, so
/// spam-tapping a refresh button or pull-to-refresh can't hammer the backend.
/// In-memory only — cooldowns are short-lived and don't need to survive restarts.
class RefreshCooldown {
  final Duration duration;
  final _lastFiredAt = <String, DateTime>{};

  RefreshCooldown({this.duration = const Duration(seconds: 3)});

  /// Records [key] as fired and returns true if it's outside its cooldown
  /// window. Returns false, leaving the previous timestamp in place, if
  /// still cooling down.
  bool tryFire(String key) {
    final now = DateTime.now();
    final last = _lastFiredAt[key];
    if (last != null && now.difference(last) < duration) return false;
    _lastFiredAt[key] = now;
    return true;
  }
}
