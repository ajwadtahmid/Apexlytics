class TimeoutConstants {
  TimeoutConstants._();

  static const Duration apiConnect = Duration(seconds: 15);
  static const Duration apiReceive = Duration(seconds: 15);

  /// Upper bound on one logical request, covering every retry and failover
  /// attempt combined — not just one. Enforced via [withOverallDeadline].
  static const Duration overallRequestDeadline = Duration(seconds: 25);
}
