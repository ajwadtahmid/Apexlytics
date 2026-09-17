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
/// On network failure, [get] and [getList] transparently fall back to the
/// most-recent cached response (stale data) rather than throwing.
class ApiService {
  late final Dio _dio;
  late final ApiCache _cache;

  /// Overridable only for tests — production callers get
  /// [TimeoutConstants.overallRequestDeadline].
  final Duration _overallDeadline;

  ApiService(ApiCacheStore cacheStore, {Duration? overallDeadline})
    : _overallDeadline =
          overallDeadline ?? TimeoutConstants.overallRequestDeadline {
    _dio = Dio(buildApiBaseOptions());
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
        _overallDeadline,
        (token) => _dio.get('/healthz', cancelToken: token),
      );
    } catch (e) {
      log.d('Warmup failed (best-effort)', error: e);
    }
  }

  /// Removes every cached response — used by "Clear all data".
  Future<void> clearCache() => _cache.clear();

  /// Returns cached data synchronously without making a network request.
  /// Returns null if no valid cache entry exists.
  ApiResult<Map<String, dynamic>>? loadCached(
    String endpoint, {
    Map<String, dynamic>? params,
  }) {
    final key = _buildCacheKey(endpoint, params);
    final cached = _cache.load(key);
    if (cached == null) return null;
    // Expose the save timestamp so callers can show "cached X ago" to the user.
    return ApiResult(
      cached.data as Map<String, dynamic>,
      staleAt: cached.savedAt,
    );
  }

  /// Fetches [endpoint] and caches the result. On [DioException], returns stale
  /// cached data if available; otherwise re-throws a user-friendly message.
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
  );

  /// Fetches [endpoint] expecting a list response and caches the result.
  /// On [DioException], returns stale cached data if available; otherwise re-throws.
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
  );

  /// Fetches [endpoint] and returns the HTTP status alongside the decoded body.
  ///
  /// Unlike [get]/[getList], which only ever see `200`, this exposes `202` too —
  /// `/games` uses it to mean "request accepted, no fresh data yet". Never
  /// caches the response.
  Future<({int status, dynamic data})> getWithStatus(
    String endpoint, {
    Map<String, dynamic>? params,
  }) async {
    try {
      final response = await withOverallDeadline(
        _overallDeadline,
        (token) =>
            _dio.get(endpoint, queryParameters: params, cancelToken: token),
      );
      final data = response.data;
      if (data is Map && data.containsKey('error')) {
        throw AppException(data['error'].toString());
      }
      return (status: response.statusCode ?? 0, data: data);
    } on DioException catch (e) {
      throw AppException(friendlyError(e));
    }
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
  }) async {
    final key = _buildCacheKey(endpoint, params);
    try {
      final response = await withOverallDeadline(
        _overallDeadline,
        (token) =>
            _dio.get(endpoint, queryParameters: params, cancelToken: token),
      );
      final data = normalizer(response.data);
      if (!noCache) await _cache.save(key, data);
      return ApiResult(data);
    } on DioException catch (e) {
      if (!noCache) {
        final cached = _cache.loadStale(key);
        if (cached != null) {
          return ApiResult(
            cacheNormalizer(cached.data),
            staleAt: cached.savedAt,
          );
        }
      }
      throw AppException(friendlyError(e));
    }
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
