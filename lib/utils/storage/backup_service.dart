import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/prefs_keys.dart';
import '../../services/ranked_history_store.dart';
import '../app_logger.dart';
import 'legend_stats_storage.dart';
import 'rp_snapshot_storage.dart';

// v2 adds the `ranked_history` section. v1 backups (prefs only) still import.
const int _kBackupVersion = 2;

const _excludedKeys = {PrefsKeys.uidSearchWarningShown};

const _excludedPrefixes = ['api_cache:', 'api_cache_ts:'];

const _staticBackupKeys = {
  PrefsKeys.profiles,
  PrefsKeys.activeProfileIndex,
  PrefsKeys.playerName,
  PrefsKeys.playerUid,
  PrefsKeys.playerPlatform,
  PrefsKeys.statsRefreshMinutes,
  PrefsKeys.compactLegendCards,
  PrefsKeys.notifyPubsMapRotation,
  PrefsKeys.notifyRankedMapRotation,
  PrefsKeys.notifyMixtapeMapRotation,
  PrefsKeys.rankedNotifyMinutes,
  PrefsKeys.pubsNotifyMinutes,
  PrefsKeys.mixtapeNotifyMinutes,
  PrefsKeys.favoriteRankedMapNames,
  PrefsKeys.favoritePubsMapNames,
  PrefsKeys.defaultTab,
  PrefsKeys.searchFavorites,
  PrefsKeys.legendStats,
  PrefsKeys.legendVisitStack,
  PrefsKeys.seasonHistory,
  PrefsKeys.statSnapshots,
};

const _dynamicBackupPrefixes = [
  legendStatsKeyPrefix,
  snapshotKeyPrefix,
];

bool _include(String key) {
  if (_excludedKeys.contains(key)) return false;
  for (final prefix in _excludedPrefixes) {
    if (key.startsWith(prefix)) return false;
  }
  if (_staticBackupKeys.contains(key)) return true;
  for (final prefix in _dynamicBackupPrefixes) {
    if (key.startsWith(prefix)) return true;
  }
  return false;
}

Map<String, dynamic> _collect(SharedPreferences prefs) {
  final result = <String, dynamic>{};
  for (final key in prefs.getKeys()) {
    if (!_include(key)) continue;
    final v = prefs.get(key);
    if (v != null) result[key] = v;
  }
  return result;
}

/// Shows a save dialog and writes backup JSON to the user's selected location.
/// Returns the file path on success, null if user cancelled.
///
/// [rankedStore], when provided, embeds the full ranked match history in the
/// same file so device migration stays a single-file operation.
Future<String?> exportBackup(
  SharedPreferences prefs, {
  RankedHistoryStore? rankedStore,
}) async {
  final payload = _collect(prefs);
  final rankedHistory = rankedStore == null
      ? const <Map<String, Object?>>[]
      : await rankedStore.exportRows();
  final envelope = {
    'version': _kBackupVersion,
    'exported_at': DateTime.now().toIso8601String(),
    'prefs': payload,
    'ranked_history': rankedHistory,
  };

  final json = const JsonEncoder.withIndent('  ').convert(envelope);
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final defaultFilename = 'apexlytics_$stamp.json';

  final dirPath = await file_selector.getDirectoryPath();

  if (dirPath == null) return null;

  final filePath = [dirPath, defaultFilename].join(Platform.pathSeparator);
  final file = File(filePath);
  await file.writeAsString(json);

  log.i('Backup exported: ${payload.length} keys, '
      '${rankedHistory.length} ranked matches → $filePath');
  return filePath;
}

sealed class ImportResult {}

class ImportCancelled extends ImportResult {}

class ImportSuccess extends ImportResult {
  final int keyCount;
  ImportSuccess(this.keyCount);
}

class ImportError extends ImportResult {
  final String message;
  ImportError(this.message);
}

/// Shows a file picker dialog, reads backup JSON, and restores all keys to [prefs].
/// Returns an [ImportResult] describing the outcome. [rankedStore], when
/// provided, restores any embedded ranked match history.
Future<ImportResult> importBackup(
  SharedPreferences prefs, {
  RankedHistoryStore? rankedStore,
}) async {
  final pickedFile = await file_selector.openFile(
    acceptedTypeGroups: [
      const file_selector.XTypeGroup(
        label: 'JSON files',
        extensions: ['json'],
      ),
    ],
  );

  if (pickedFile == null) return ImportCancelled();

  try {
    final raw = await pickedFile.readAsString();
    final envelope = jsonDecode(raw) as Map<String, dynamic>;

    final version = envelope['version'];
    if (version is! int || version > _kBackupVersion) {
      return ImportError('Unsupported backup version ($version).');
    }

    final prefsData = envelope['prefs'];
    if (prefsData is! Map<String, dynamic>) {
      return ImportError('Invalid prefs structure in backup file.');
    }
    for (final entry in prefsData.entries) {
      final v = entry.value;
      if (v is String) {
        await prefs.setString(entry.key, v);
      } else if (v is int) {
        await prefs.setInt(entry.key, v);
      } else if (v is bool) {
        await prefs.setBool(entry.key, v);
      } else if (v is double) {
        await prefs.setDouble(entry.key, v);
      } else {
        log.w('Backup import: skipping unsupported type for "${entry.key}": ${v.runtimeType}');
      }
    }

    // Restore embedded ranked history (absent in v1 backups).
    final rankedHistory = envelope['ranked_history'];
    if (rankedHistory is List && rankedStore != null) {
      await rankedStore.importRows(rankedHistory);
      log.i('Backup restored ${rankedHistory.length} ranked matches');
    }

    log.i('Backup restored: ${prefsData.length} keys from v$version backup');
    return ImportSuccess(prefsData.length);
  } on FormatException catch (e) {
    log.w('Backup import failed — invalid JSON', error: e);
    return ImportError('The selected file is not a valid backup.');
  } catch (e) {
    log.w('Backup import failed', error: e);
    return ImportError('Failed to read the backup file.');
  }
}
