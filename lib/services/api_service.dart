import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/timeout_constants.dart';
import '../env/env.dart';
import '../utils/api_base_options.dart';
import '../utils/api_cache.dart';
import '../utils/api_deadline.dart';
import '../utils/app_logger.dart';
import '../utils/error_messages.dart' show AppException, friendlyError;
import '../utils/retry_interceptor.dart';
import '../utils/storage/api_cache_store.dart';

export '../utils/api_cache.dart' show ApiResult;

/// HTTP client wrapping Dio with a write-through disk cache.
/// On a transient failure (offline, timeout, 5xx, 429), [get]/[getList] fall back to the
/// cached response (stale); a definite answer like 404 is still thrown.
class ApiService {
  late final Dio _dio;
  late final ApiCache _cache;

  /// [httpClientAdapter] is a test seam: it replaces the transport only, so
  /// requests still run through the real interceptors and error handling.
  ApiService(
    ApiCacheStore cacheStore, {
    @visibleForTesting HttpClientAdapter? httpClientAdapter,
  }) {
    _dio = Dio(buildApiBaseOptions());
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestHeader: false,
          requestBody: false,
          responseHeader: false,
          // Bodies can be large — log status lines only.
          responseBody: false,
          logPrint: (o) => log.d(o.toString()),
        ),
      );
    }
    _dio.interceptors.add(
      RetryInterceptor(dio: _dio, backupBaseUrl: Env.proxyUrlBackup),
    );
    _cache = ApiCache(cacheStore);
    // Fire-and-forget: a failed prime just means synchronous cache reads
    // return null until the next successful save, not a startup crash — the
    // same tolerance app.dart's snapshot priming already accepts for the
    // exact same "reads on frame 1, storage is async" reason.
    unawaited(
      _cache.primeFromDisk().catchError((Object e) {
        log.w('API cache priming failed', error: e);
      }),
    );
  }

  /// Opens the underlying TCP connection so the first real request skips the
  /// handshake latency. Failures are silently swallowed — this is best-effort.
  Future<void> warmup() async {
    try {
      await withOverallDeadline(
        TimeoutConstants.overallRequestDeadline,
        (token) => _dio.get('/healthz', cancelToken: token),
      );
    } catch (e) {
      log.d('Warmup failed (best-effort)', error: e);
    }
  }

  /// Removes every cached response — used by "Clear all data" and by "Clear
  /// cached responses".
  Future<void> clearCache() => _cache.clear();

  /// How many responses are cached, and about how large they are.
  ({int entries, int bytes}) get cacheUsage => _cache.usage;

  /// Returns cached data synchronously without making a network request.
  /// Returns null if no valid cache entry exists. With [allowStale] an entry
  /// past its TTL is returned too, for a caller that would rather show old data
  /// than none.
  ApiResult<Map<String, dynamic>>? loadCached(
    String endpoint, {
    Map<String, dynamic>? params,
    bool allowStale = false,
  }) {
    final key = _buildCacheKey(endpoint, params);
    final cached = allowStale ? _cache.loadStale(key) : _cache.load(key);
    if (cached == null) return null;
    // Expose the save timestamp so callers can show "cached X ago" to the user.
    return ApiResult(
      cached.data as Map<String, dynamic>,
      staleAt: cached.savedAt,
    );
  }

  /// Fetches [endpoint] and caches the result. On a transient failure returns stale cached
  /// data if available; a definite answer (404, 401…) is thrown. Otherwise re-throws a
  /// friendly message.
  /// Pass [noCache] = true to skip both read and write (e.g. search-by-name).
  Future<ApiResult<Map<String, dynamic>>> get(
    String endpoint, {
    Map<String, dynamic>? params,
    bool noCache = false,
  }) => _request(
    endpoint,
    params: params,
    noCache: noCache,
    // Defensive fallback: wrap non-map responses (e.g. scalars, lists) so the
    // caller always receives a Map<String, dynamic>. The wrapped value is in '_raw'.
    normalizer: (d) {
      if (d is Map && d.containsKey('error')) {
        throw AppException(d['error'].toString());
      }
      return d is Map<String, dynamic> ? d : {'_raw': d};
    },
    cacheNormalizer: (d) => d as Map<String, dynamic>,
    // A body that had to be wrapped (an HTML page from an intermediary, say)
    // or that is the upstream API's own `{"Error": ...}` is not a response
    // worth keeping: saved, it would replace the last good copy, and the
    // offline fallback would then serve it as the player's stats.
    cacheable: (d) => d is Map<String, dynamic> && !d.containsKey('Error'),
  );

  /// Fetches [endpoint] expecting a list response and caches the result.
  /// Falls back to stale cache on the same failures as [get].
  /// Pass [noCache] = true to skip both read and write.
  Future<ApiResult<List<dynamic>>> getList(
    String endpoint, {
    Map<String, dynamic>? params,
    bool noCache = false,
  }) => _request(
    endpoint,
    params: params,
    noCache: noCache,
    normalizer: (d) {
      if (d is List) return d;
      if (d is Map && d.containsKey('error')) {
        throw AppException(d['error'].toString());
      }
      return <dynamic>[];
    },
    cacheNormalizer: (d) => d as List<dynamic>,
    // Not a list: the normalizer's empty stand-in, not an answer to keep.
    cacheable: (d) => d is List,
  );

  /// Fetches [endpoint] and returns the HTTP status alongside the decoded body.
  ///
  /// Unlike [get]/[getList], which only ever see `200`, this exposes `202` too —
  /// `/games` uses it to mean "request accepted, no fresh data yet". Never
  /// caches the response.
  ///
  /// [failover] false keeps the request on the primary host (see
  /// [kNoFailoverKey]).
  Future<({int status, dynamic data})> getWithStatus(
    String endpoint, {
    Map<String, dynamic>? params,
    bool failover = true,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await withOverallDeadline(
        TimeoutConstants.overallRequestDeadline,
        (token) => _dio.get(
          endpoint,
          queryParameters: params,
          cancelToken: token,
          options: failover && headers == null
              ? null
              : Options(
                  headers: headers,
                  extra: failover ? null : {kNoFailoverKey: true},
                ),
        ),
      );
      final data = response.data;
      if (data is Map && data.containsKey('error')) {
        // Carries the real status, unlike a bare AppException — a caller
        // (e.g. rankedSyncProvider) needs to tell a genuine 4xx apart from a
        // transport failure with no status to report at all.
        throw AppException(
          data['error'].toString(),
          status: response.statusCode,
        );
      }
      return (status: response.statusCode ?? 0, data: data);
    } on DioException catch (e) {
      // Dio turns every non-2xx into a DioException, so its status has to be
      // carried over here or a rejected request (a wrong client token, say)
      // looks the same as being offline.
      final response = e.response;
      throw AppException(
        friendlyError(e),
        status: response?.statusCode,
        retryAfter: _retryAfter(response),
      );
    }
  }

  /// A `Retry-After` given in seconds, or null. (The HTTP-date form isn't
  /// used by the proxy.)
  static Duration? _retryAfter(Response<dynamic>? response) {
    final seconds = int.tryParse(
      response?.headers.value('retry-after')?.trim() ?? '',
    );
    return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
  }

  // Shared fetch-cache-fallback logic used by both [get] and [getList].
  // [normalizer] transforms the raw response body; [cacheNormalizer] casts
  // the stored cache payload. Only [DioException] triggers the fallback —
  // exceptions thrown by [normalizer] propagate directly to the caller.
  Future<ApiResult<T>> _request<T extends Object>(
    String endpoint, {
    Map<String, dynamic>? params,
    bool noCache = false,
    required T Function(dynamic) normalizer,
    required T Function(dynamic) cacheNormalizer,
    // Whether the raw response body may be saved as the last good copy.
    required bool Function(dynamic) cacheable,
  }) async {
    final key = _buildCacheKey(endpoint, params);
    // Read before the request: a clear while it's in flight must not get this written back.
    final cacheGeneration = _cache.generation;
    try {
      final response = await withOverallDeadline(
        TimeoutConstants.overallRequestDeadline,
        (token) =>
            _dio.get(endpoint, queryParameters: params, cancelToken: token),
      );
      final data = normalizer(response.data);
      if (!noCache && cacheable(response.data)) {
        // Best-effort: a cache-write failure (e.g. disk full) must not turn
        // an already-successful fetch into a thrown error.
        try {
          await _cache.save(key, data, ifGeneration: cacheGeneration);
        } catch (e) {
          log.w('API cache save failed', error: e);
        }
      }
      return ApiResult(data);
    } on DioException catch (e) {
      if (!noCache && _canServeStale(e)) {
        final cached = _cache.loadStale(key);
        if (cached != null) {
          return ApiResult(
            cacheNormalizer(cached.data),
            staleAt: cached.savedAt,
          );
        }
      }
      // Status and Retry-After kept, as in [getWithStatus].
      throw AppException(
        friendlyError(e),
        status: e.response?.statusCode,
        retryAfter: _retryAfter(e.response),
      );
    }
  }

  /// Definite answers (bad token, refused, unknown player or platform); old data would hide
  /// the problem, e.g. a vanished player loading from cache.
  static const _definitiveStatuses = {401, 403, 404, 410};

  /// Whether a failed request may fall back to stale cache: no answer, or anything but
  /// [_definitiveStatuses].
  static bool _canServeStale(DioException e) {
    final status = e.response?.statusCode;
    return status == null || !_definitiveStatuses.contains(status);
  }

  String _buildCacheKey(String endpoint, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return endpoint;
    // Sort params to produce a stable cache key regardless of insertion order.
    final sorted = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final uri = Uri(
      path: endpoint,
      queryParameters: {for (final e in sorted) e.key: '${e.value}'},
    );
    return uri.toString();
  }
}
