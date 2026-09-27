class TimeoutConstants {
  TimeoutConstants._();

  static const Duration apiConnect = Duration(seconds: 15);
  static const Duration apiReceive = Duration(seconds: 15);

  /// Same-host retries `RetryInterceptor` makes on a fast failure (5xx,
  /// refused connection), and the delay before the first one.
  static const int retriesPerHost = 1;
  static const Duration retryDelay = Duration(seconds: 1);

  /// The longest one attempt can stall before Dio gives up: whichever of
  /// connect/receive is longer (stalling on both is rare enough to ignore).
  static final Duration _attempt = apiConnect > apiReceive
      ? apiConnect
      : apiReceive;

  /// Upper bound on one logical request, covering every retry and failover
  /// attempt combined. Enforced via [withOverallDeadline].
  ///
  /// Sized for the worst chain `RetryInterceptor` runs: one timed-out primary
  /// attempt (a timeout moves straight to the backup), then the backup's
  /// full ladder — attempt, retry delay, retry — which is what gives a
  /// sleeping backup time to wake up. 15+15+1+15 = 46s. Derived rather than
  /// written down, since a shorter deadline would silently cut the failover
  /// it exists to allow.
  static final Duration overallRequestDeadline =
      _attempt +
      (_attempt * (retriesPerHost + 1)) +
      retryDelay * retriesPerHost;

  /// The background map-rotation fetch's equivalent, but capped by the OS
  /// budget rather than sized to the failover chain: iOS gives a background
  /// fetch ~30s total, and a task it kills never records its result. 20s
  /// leaves room for plugin init before and scheduling alerts after.
  static const Duration backgroundFetchDeadline = Duration(seconds: 20);
}
