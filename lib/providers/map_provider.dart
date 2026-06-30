import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/map_rotation.dart';
import '../models/seasonal_maps.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import 'api_provider.dart';
import 'settings_provider.dart';

class MapRotationNotifier extends AsyncNotifier<ApiResult<MapRotation>> {
  @override
  Future<ApiResult<MapRotation>> build() {
    return ref.watch(mapServiceProvider).getMapRotation();
  }
}

final mapRotationProvider =
    AsyncNotifierProvider<MapRotationNotifier, ApiResult<MapRotation>>(
      MapRotationNotifier.new,
    );

class SeasonalMapsNotifier extends AsyncNotifier<SeasonalMaps> {
  static const String _cacheKey = SeasonalMaps.cacheKey;

  @override
  Future<SeasonalMaps> build() async {
    final prefs = ref.watch(sharedPreferencesProvider);
    final apiService = ref.watch(apiServiceProvider);

    final SeasonalMaps? cached = _loadFromCache(prefs);

    try {
      final result = await apiService.get('/maps', noCache: true);
      final fresh = SeasonalMaps.fromJson(result.data);

      if (_hasChanged(cached, fresh)) {
        unawaited(_saveToCache(prefs, fresh));
      }

      return fresh;
    } catch (e) {
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  SeasonalMaps? _loadFromCache(SharedPreferences prefs) {
    final jsonStr = prefs.getString(_cacheKey);
    if (jsonStr == null) return null;
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SeasonalMaps.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveToCache(SharedPreferences prefs, SeasonalMaps maps) async {
    try {
      final jsonStr = jsonEncode(maps.toJson());
      await prefs.setString(_cacheKey, jsonStr);
    } catch (e) {
      log.d('Failed to cache seasonal maps', error: e);
    }
  }

  bool _hasChanged(SeasonalMaps? old, SeasonalMaps? fresh) {
    if (old == null || fresh == null) return true;

    if (old.ranked.length != fresh.ranked.length || old.pubs.length != fresh.pubs.length) {
      return true;
    }

    for (var i = 0; i < old.ranked.length; i++) {
      if (old.ranked[i].id != fresh.ranked[i].id) return true;
    }
    for (var i = 0; i < old.pubs.length; i++) {
      if (old.pubs[i].id != fresh.pubs[i].id) return true;
    }

    return false;
  }
}

final seasonalMapsProvider =
    AsyncNotifierProvider<SeasonalMapsNotifier, SeasonalMaps>(
      SeasonalMapsNotifier.new,
    );
