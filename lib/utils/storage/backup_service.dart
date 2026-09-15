import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/prefs_keys.dart';
import '../app_logger.dart';
import 'legend_stats_storage.dart';
import 'ranked_history_store.dart';
import 'rp_snapshot_storage.dart';

// v1: prefs only. v2 adds `ranked_history`. v3 adds `stat_snapshots` (schema
// v8 moved these to SQLite); older files still carry them as prefs keys,
// which `migrateSnapshotsFromPrefs` picks up after restore.
const int _kBackupVersion = 3;

const _excludedKeys = {
  PrefsKeys.uidSearchWarningShown,
  // Device-local first-run state: a restored backup on a fresh install should
  // still show the orientation tour once, and shouldn't suppress it elsewhere.
  PrefsKeys.onboardingVersion,
};

const _excludedPrefixes = ['api_cache:', 'api_cache_ts:'];

const _staticBackupKeys = {
  PrefsKeys.profiles,
  PrefsKeys.activeProfileIndex,
  PrefsKeys.playerName,
  PrefsKeys.playerUid,
  PrefsKeys.playerPlatform,
  PrefsKeys.statsRefreshMinutes,
  PrefsKeys.compactLegendCards,
  PrefsKeys.keepScreenOn,
  PrefsKeys.notifyPubsMapRotation,
  PrefsKeys.notifyRankedMapRotation,
  PrefsKeys.notifyMixtapeMapRotation,
  PrefsKeys.notifyWildcardMapRotation,
  PrefsKeys.rankedNotifyMinutes,
  PrefsKeys.pubsNotifyMinutes,
  PrefsKeys.mixtapeNotifyMinutes,
  PrefsKeys.wildcardNotifyMinutes,
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
  // Deliberate user input, and the second setting to escape backups by being
  // a UID-scoped key nobody added here. See the exhaustiveness test.
  PrefsKeys.rankGoalPrefix,
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

/// Whether [key] is captured by backup export/import. Exposed for tests that
/// guard against a newly-added persisted setting silently escaping backups —
/// the failure mode that dropped the Wildcard notification settings.
@visibleForTesting
bool backupIncludesKey(String key) => _include(key);

/// Masks any embedded UID in a pref key before logging - `log.w` forwards to
/// Sentry, and UID-scoped keys (`rank_goal_1006838015507`) carry the player
/// identifier in the key name itself.
String _redactUid(String key) => key.replaceAll(RegExp(r'\d{10,20}'), '<uid>');

/// Restores [prefsData] into [prefs], skipping disallowed keys and dispatching
/// each value to the matching typed `SharedPreferences` setter. Extracted from
/// [commitBackupImport] so the type-dispatch is testable without a file picker.
@visibleForTesting
Future<void> restorePrefsData(
  SharedPreferences prefs,
  Map<String, dynamic> prefsData,
) async {
  for (final entry in prefsData.entries) {
    if (!_include(entry.key)) {
      log.w(
        'Backup import: skipping disallowed key "${_redactUid(entry.key)}"',
      );
      continue;
    }
    final v = entry.value;
    if (v is String) {
      await prefs.setString(entry.key, v);
    } else if (v is int) {
      await prefs.setInt(entry.key, v);
    } else if (v is bool) {
      await prefs.setBool(entry.key, v);
    } else if (v is double) {
      await prefs.setDouble(entry.key, v);
    } else if (v is List) {
      await prefs.setStringList(entry.key, v.map((e) => e.toString()).toList());
    } else {
      log.w(
        'Backup import: skipping unsupported type for '
        '"${_redactUid(entry.key)}": ${v.runtimeType}',
      );
    }
  }
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
  final statSnapshots = rankedStore == null
      ? const <Map<String, Object?>>[]
      : await rankedStore.exportSnapshotRows();
  final envelope = {
    'version': _kBackupVersion,
    'exported_at': DateTime.now().toIso8601String(),
    'prefs': payload,
    'ranked_history': rankedHistory,
    'stat_snapshots': statSnapshots,
  };

  final json = const JsonEncoder.withIndent('  ').convert(envelope);
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final defaultFilename = 'apexlytics_$stamp.json';

  if (Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$defaultFilename';
    await File(filePath).writeAsString(json);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(filePath, mimeType: 'application/json')]),
    );
    log.i(
      'Backup shared: ${payload.length} keys, '
      '${rankedHistory.length} ranked matches → $filePath',
    );
    return filePath;
  }

  final dirPath = await file_selector.getDirectoryPath();
  if (dirPath == null) return null;

  final filePath = [dirPath, defaultFilename].join(Platform.pathSeparator);
  await File(filePath).writeAsString(json);

  log.i(
    'Backup exported: ${payload.length} keys, '
    '${rankedHistory.length} ranked matches → $filePath',
  );
  return filePath;
}

// Cancellation is a PreviewResult concern now (see previewBackup) -
// commitBackupImport is only ever called after a file was already picked,
// so ImportResult itself no longer needs an ImportCancelled variant.
sealed class ImportResult {}

class ImportSuccess extends ImportResult {
  final int keyCount;
  ImportSuccess(this.keyCount);
}

class ImportError extends ImportResult {
  final String message;
  ImportError(this.message);
}

/// A parsed, not-yet-committed backup file, shown to the user before
/// [commitBackupImport] writes anything. [newMatchCount] is the point of it:
/// distinguishing "this backup mostly
/// duplicates what you already have" from "this restores 1,200 matches
/// you're about to see for the first time" for an operation that still
/// merges two histories together irreversibly.
class BackupPreview {
  final int version;
  final DateTime? exportedAt;
  final int profileCount;
  final int matchCount;
  final int newMatchCount;

  // Kept so commitBackupImport can write without re-picking or re-parsing
  // the file.
  final Map<String, dynamic> _envelope;

  const BackupPreview._({
    required this.version,
    required this.exportedAt,
    required this.profileCount,
    required this.matchCount,
    required this.newMatchCount,
    required Map<String, dynamic> envelope,
  }) : _envelope = envelope;
}

sealed class PreviewResult {}

class PreviewCancelled extends PreviewResult {}

class PreviewReady extends PreviewResult {
  final BackupPreview preview;
  PreviewReady(this.preview);
}

class PreviewError extends PreviewResult {
  final String message;
  PreviewError(this.message);
}

/// Shows a file picker dialog and parses+summarizes the selected backup,
/// without writing anything. Pass the [BackupPreview] from a [PreviewReady]
/// result to [commitBackupImport] to actually restore it.
Future<PreviewResult> previewBackup({RankedHistoryStore? rankedStore}) async {
  final pickedFile = await file_selector.openFile(
    acceptedTypeGroups: [
      const file_selector.XTypeGroup(
        label: 'JSON files',
        extensions: ['json'],
        uniformTypeIdentifiers: ['public.json'],
      ),
    ],
  );

  if (pickedFile == null) return PreviewCancelled();

  try {
    final raw = await pickedFile.readAsString();
    final envelope = jsonDecode(raw) as Map<String, dynamic>;

    final version = envelope['version'];
    // Lower-bounded too, not just upper-bounded: a malformed or hand-edited
    // file with e.g. `"version": 0` used to pass this guard and be treated
    // as a v1 file by the parsing below, rather than being rejected here.
    if (version is! int || version < 1 || version > _kBackupVersion) {
      return PreviewError('Unsupported backup version ($version).');
    }

    final prefsData = envelope['prefs'];
    if (prefsData is! Map<String, dynamic>) {
      return PreviewError('Invalid prefs structure in backup file.');
    }

    return PreviewReady(
      BackupPreview._(
        version: version,
        exportedAt: DateTime.tryParse(envelope['exported_at'] as String? ?? ''),
        profileCount: _countProfiles(prefsData),
        matchCount: _rowCount(envelope['ranked_history']),
        newMatchCount: await _countNewMatches(
          envelope['ranked_history'],
          rankedStore,
        ),
        envelope: envelope,
      ),
    );
  } on FormatException catch (e) {
    log.w('Backup preview failed — invalid JSON', error: e);
    return PreviewError('The selected file is not a valid backup.');
  } catch (e) {
    log.w('Backup preview failed', error: e);
    return PreviewError('Failed to read the backup file.');
  }
}

// player_profiles is itself a JSON-encoded string within prefs (see
// PlayerSettingsNotifier._saveProfiles), not a nested object — parsed here
// only to count entries for the preview, independent of restorePrefsData's
// own (separate) handling of the same key.
int _countProfiles(Map<String, dynamic> prefsData) {
  final raw = prefsData[PrefsKeys.profiles];
  if (raw is! String) return 0;
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded.length : 0;
  } on FormatException {
    return 0;
  }
}

int _rowCount(Object? rows) => rows is List ? rows.length : 0;

/// How many of [rows] (raw `ranked_history` entries) aren't already in
/// [rankedStore] by id. Matches [rankedStore]'s own dedup key, so this is
/// exact, not an estimate. 0 when there's no store to compare against.
Future<int> _countNewMatches(Object? rows, RankedHistoryStore? rankedStore) async {
  if (rows is! List || rows.isEmpty || rankedStore == null) return 0;
  final existing = await rankedStore.allIds();
  return rows.where((r) => r is Map && !existing.contains(r['id'])).length;
}

/// Restores a previously-[previewBackup]'d file. [rankedStore], when
/// provided, restores any embedded ranked match history.
Future<ImportResult> commitBackupImport(
  BackupPreview preview,
  SharedPreferences prefs, {
  RankedHistoryStore? rankedStore,
}) async {
  final envelope = preview._envelope;
  final prefsData = envelope['prefs'] as Map<String, dynamic>;

  try {
    // Database sections first, prefs last - no transaction spans both stores,
    // so a malformed file should fail before any pref commits, not after.
    final rankedHistory = envelope['ranked_history']; // absent in v1
    if (rankedHistory is List && rankedStore != null) {
      await rankedStore.importRows(rankedHistory);
      log.i('Backup restored ${rankedHistory.length} ranked matches');
    }

    // Absent in v1/v2, where snapshots rode along in `prefs` instead and are
    // picked up by migrateSnapshotsFromPrefs below.
    final statSnapshots = envelope['stat_snapshots'];
    if (statSnapshots is List && rankedStore != null) {
      await rankedStore.importSnapshotRows(statSnapshots);
      log.i('Backup restored ${statSnapshots.length} RP snapshots');
    }

    await restorePrefsData(prefs, prefsData);
    if (rankedStore != null) {
      // A v1/v2 file restores its snapshots as prefs keys; drain them now
      // rather than leaving the graph empty until the next launch. No-op for
      // a v3 file, which carries no legacy keys.
      await migrateSnapshotsFromPrefs(prefs, rankedStore);
    }
    resetSnapshotCache();

    log.i(
      'Backup restored: ${prefsData.length} keys from v${preview.version} backup',
    );
    return ImportSuccess(prefsData.length);
  } catch (e) {
    log.w('Backup import failed', error: e);
    return ImportError('Failed to restore the backup file.');
  }
}
