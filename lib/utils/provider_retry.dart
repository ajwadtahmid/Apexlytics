import 'error_messages.dart' show AppException;

/// How many times Riverpod re-runs a provider that threw. Riverpod 3's own
/// default is ten, which turns one failing request into a burst of them (each
/// already retried and failed over by `RetryInterceptor`) while the UI sits on
/// a spinner.
const int kProviderMaxRetries = 2;

/// App-wide `ProviderScope.retry`: re-run a failed provider only when the
/// failure may clear by itself, and only a couple of times.
///
/// - An [AppException] with a definite status (401/403/404/410/429, ...) is
///   never retried: the server already answered, and asking again gets the
///   same answer — or, for a 429, makes the rate limiting worse.
/// - A 5xx or a transport failure (no status) is retried after a pause long
///   enough to be worth it, since `ApiService` has already spent its own
///   retries and failover on the immediate attempts.
/// - Any other exception (a storage hiccup, say) is retried; an [Error] is a
///   bug and never is.
Duration? transientProviderRetry(int retryCount, Object error) {
  if (retryCount >= kProviderMaxRetries) return null;
  if (error is Error) return null;
  if (error is AppException) {
    final status = error.status;
    if (status != null && status < 500) return null;
  }
  return Duration(seconds: 3 + retryCount * 5);
}
