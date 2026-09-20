import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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

// Historical: the API response cache used to live under these prefixes in
// prefs before moving to its own SQLite database. Nothing writes these keys
// anymore — kept as a harmless exclusion in case anything ever does again.
const _excludedPrefixes = ['api_cache:', 'api_cache_ts:'];

const _staticBackupKeys = {
  PrefsKeys.profiles,
  PrefsKeys.activeProfileIndex,
  PrefsKeys.playerName,
  PrefsKeys.playerUid,
  PrefsKeys.playerPlatform,
  PrefsKeys.statsRefreshMinutes,
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

/// Every prefs key a restore of [prefsData] touches: written (present in the
/// backup and allowlisted) or cleared (a [_staticBackupKeys] entry that's
/// absent from the backup but exists on-device — see [restorePrefsData]'s
/// full-replace doc). The single source of truth for that key set, so
/// [restorePrefsData]'s own snapshot and [commitBackupImport]'s outer one
/// can never disagree about what a restore is about to change.
@visibleForTesting
Set<String> prefsKeysTouchedByRestore(
  SharedPreferences prefs,
  Map<String, dynamic> prefsData,
) {
  final written = prefsData.keys.where(_include);
  final cleared = prefs.getKeys().where(
    (k) => _staticBackupKeys.contains(k) && !prefsData.containsKey(k),
  );
  return {...written, ...cleared};
}

Future<void> _setTyped(SharedPreferences prefs, String key, Object? v) async {
  if (v is String) {
    await prefs.setString(key, v);
  } else if (v is int) {
    await prefs.setInt(key, v);
  } else if (v is bool) {
    await prefs.setBool(key, v);
  } else if (v is double) {
    await prefs.setDouble(key, v);
  } else if (v is List) {
    await prefs.setStringList(key, v.map((e) => e.toString()).toList());
  }
}

/// A captured pre-write value for every key in a set, restorable on demand.
/// Shared by [restorePrefsData] (rolls back on its own failure) and
/// [commitBackupImport] (also rolls back if the database transaction fails
/// *after* [restorePrefsData] already succeeded — a failure its own
/// snapshot can no longer see once its call has resolved). Applying both
/// for the same failure is harmless — the second just re-writes what the
/// first already restored.
class _PrefsSnapshot {
  final SharedPreferences _prefs;
  final Map<String, Object?> _values;

  _PrefsSnapshot._(this._prefs, this._values);

  factory _PrefsSnapshot.capture(
    SharedPreferences prefs,
    Iterable<String> keys,
  ) => _PrefsSnapshot._(prefs, {for (final k in keys) k: prefs.get(k)});

  /// Restores every captured key to its pre-snapshot value, or removes it if
  /// it didn't exist before. Best-effort: one key failing to roll back must
  /// not stop the rest of the rollback from running.
  Future<void> rollback() async {
    for (final entry in _values.entries) {
      try {
        if (entry.value == null) {
          await _prefs.remove(entry.key);
        } else {
          await _setTyped(_prefs, entry.key, entry.value);
        }
      } catch (e) {
        log.w(
          'Backup import rollback failed for "${_redactUid(entry.key)}"',
          error: e,
        );
      }
    }
  }
}

/// Restores [prefsData] into [prefs], skipping disallowed keys and dispatching
/// each value to the matching typed `SharedPreferences` setter. Extracted from
/// [commitBackupImport] so the type-dispatch is testable without a file picker.
///
/// Full-replace, not merge, for *static* keys: a setting the backup doesn't
/// mention is cleared, matching what "restore" means to a user. **Not**
/// applied to the dynamic per-UID prefixes — a device can hold multiple
/// profiles, and sweeping "not in this backup" there would delete a
/// *different* profile's stats the backup never claimed to describe.
/// Dynamic keys stay pure merge: overwritten if present, untouched otherwise.
///
/// Snapshots every touched key first and rolls it all back if a write
/// throws partway through — the *prefs* half is atomic on its own;
/// [commitBackupImport] adds a real database transaction plus its own
/// outer [_PrefsSnapshot] for the narrower gap that leaves open.
@visibleForTesting
Future<void> restorePrefsData(
  SharedPreferences prefs,
  Map<String, dynamic> prefsData,
) async {
  final touched = prefsKeysTouchedByRestore(prefs, prefsData);
  final toClear = touched.where((k) => !prefsData.containsKey(k));
  final snapshot = _PrefsSnapshot.capture(prefs, touched);

  try {
    for (final entry in prefsData.entries) {
      if (!_include(entry.key)) {
        log.w(
          'Backup import: skipping disallowed key "${_redactUid(entry.key)}"',
        );
        continue;
      }
      final v = entry.value;
      if (v is String || v is int || v is bool || v is double || v is List) {
        await _setTyped(prefs, entry.key, v);
      } else {
        log.w(
          'Backup import: skipping unsupported type for '
          '"${_redactUid(entry.key)}": ${v.runtimeType}',
        );
      }
    }
    for (final key in toClear) {
      await prefs.remove(key);
    }
  } catch (e) {
    await snapshot.rollback();
    rethrow;
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

/// JSON-encodes then gzip-compresses [envelope] — the CPU-bound half of
/// [exportBackup], run via [Isolate.run] rather than inline so it doesn't
/// block the UI isolate. A top-level function with no captured instance
/// state, so it's safe to send to the spawned isolate; [envelope] is plain
/// JSON-safe types throughout, which cross the isolate boundary fine.
List<int> _encodeAndCompress(Map<String, Object?> envelope) {
  // No indentation — this file is never hand-read, and pretty-printing
  // roughly doubles its size for no benefit.
  final json = jsonEncode(envelope);
  // Gzipped on top of that: the JSON is highly repetitive (same column names
  // on every row), so this compresses very well. previewBackup's file picker
  // accepts `.gz` directly (see decompressIfGzipped) via the app's own
  // document picker, so restoring stays one step as long as the user goes
  // through "Restore backup" rather than opening the file from a system file
  // manager (which may try to extract `.gz` first).
  return gzip.encode(utf8.encode(json));
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

  // Off the UI isolate (see [_encodeAndCompress]) — a multi-thousand-match
  // history is real CPU work, and doing it inline would freeze the UI on
  // exactly the operation (device migration) where a freeze is most alarming.
  final compressed = await Isolate.run(() => _encodeAndCompress(envelope));
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final defaultFilename = 'apexlytics_$stamp.json.gz';

  if (Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$defaultFilename';
    await File(filePath).writeAsBytes(compressed);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(filePath, mimeType: 'application/gzip')]),
    );
    // Path deliberately omitted: on desktop it can embed the OS username,
    // and log.i reaches Sentry as a breadcrumb in release builds — see the
    // privacy rule in app_logger.dart.
    log.i(
      'Backup shared: ${payload.length} keys, '
      '${rankedHistory.length} ranked matches, '
      '${compressed.length} bytes compressed',
    );
    return filePath;
  }

  final dirPath = await file_selector.getDirectoryPath();
  if (dirPath == null) return null;

  final filePath = [dirPath, defaultFilename].join(Platform.pathSeparator);
  await File(filePath).writeAsBytes(compressed);

  // Path omitted for the same reason as the iOS branch above.
  log.i(
    'Backup exported: ${payload.length} keys, '
    '${rankedHistory.length} ranked matches, '
    '${compressed.length} bytes compressed',
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

  /// Size of the *decompressed* JSON, in bytes — what actually ends up in
  /// memory as a string and a parsed structure, regardless of how small
  /// gzip made the file on disk. Drives the large-backup notice in the
  /// import summary.
  final int sizeBytes;

  // Kept so commitBackupImport can write without re-picking or re-parsing
  // the file.
  final Map<String, dynamic> _envelope;

  const BackupPreview._({
    required this.version,
    required this.exportedAt,
    required this.profileCount,
    required this.matchCount,
    required this.newMatchCount,
    required this.sizeBytes,
    required this._envelope,
  });

  /// Builds a preview directly from an already-parsed envelope, skipping the
  /// file picker [previewBackup] normally goes through. Lets a test exercise
  /// [commitBackupImport] end to end (real JSON encode/decode, real
  /// [RankedHistoryStore], real prefs) without mocking `file_selector`.
  @visibleForTesting
  factory BackupPreview.forTesting({
    required int version,
    DateTime? exportedAt,
    int profileCount = 0,
    int matchCount = 0,
    int newMatchCount = 0,
    int sizeBytes = 0,
    required Map<String, dynamic> envelope,
  }) => BackupPreview._(
    version: version,
    exportedAt: exportedAt,
    profileCount: profileCount,
    matchCount: matchCount,
    newMatchCount: newMatchCount,
    sizeBytes: sizeBytes,
    envelope: envelope,
  );
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
        label: 'Backup files',
        // 'gz' covers the current gzipped export; 'json' keeps older,
        // uncompressed backups (from before this file started gzipping
        // exports) importable.
        extensions: ['gz', 'json'],
        uniformTypeIdentifiers: ['public.json', 'org.gnu.gnu-zip-archive'],
      ),
    ],
  );

  if (pickedFile == null) return PreviewCancelled();

  try {
    final rawBytes = await pickedFile.readAsBytes();
    final jsonBytes = decompressIfGzipped(rawBytes);
    final rawJson = utf8.decode(jsonBytes);
    final envelope = jsonDecode(rawJson) as Map<String, dynamic>;

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
        sizeBytes: jsonBytes.length,
        envelope: envelope,
      ),
    );
  } on BackupTooLargeException {
    log.w('Backup preview failed — decompressed size exceeded the cap');
    return PreviewError('This backup is too large to restore.');
  } on BackupCorruptedException catch (e) {
    // Realistically a partially-downloaded file from cloud storage, not a
    // generic I/O problem — worth its own message rather than the catch-all.
    log.w('Backup preview failed — corrupted gzip stream', error: e);
    return PreviewError(
      'This backup file appears to be corrupted or incomplete. Try '
      're-downloading or re-exporting it.',
    );
  } on FormatException catch (e) {
    log.w('Backup preview failed — invalid JSON', error: e);
    return PreviewError('The selected file is not a valid backup.');
  } catch (e) {
    log.w('Backup preview failed', error: e);
    return PreviewError('Failed to read the backup file.');
  }
}

/// Hard ceiling on a picked backup file's *decompressed* size. Gzip has no
/// bound relating compressed to decompressed size — a crafted or corrupted
/// `.gz` a few MB on disk can expand to gigabytes, and decoding it all at
/// once allocates for that before anything can reject it. 256 MiB is far
/// beyond any real export, so this only fires on a file that isn't legitimate.
const int _kMaxDecompressedBackupBytes = 256 * 1024 * 1024;

/// Thrown by [decompressIfGzipped] when decoding would exceed
/// [_kMaxDecompressedBackupBytes]. Caught in [previewBackup] and turned into
/// a user-facing [PreviewError] rather than propagating as a generic failure.
class BackupTooLargeException implements Exception {
  const BackupTooLargeException();
}

/// Thrown by [decompressIfGzipped] when the gzip stream itself is malformed
/// — distinct from [BackupTooLargeException] (well-formed but too big) and
/// from a JSON [FormatException] (well-formed and correctly sized, but not
/// valid JSON once decompressed). Given its own message in [previewBackup],
/// since a truncated cloud-storage download is a more specific failure than
/// either of those.
class BackupCorruptedException implements Exception {
  const BackupCorruptedException();
}

/// Accumulates decoded gzip output, refusing to grow past [maxBytes]. Used as
/// the sink [GZipCodec.decoder]'s chunked conversion writes into, so
/// [decompressIfGzipped] can abort mid-decode instead of only finding out
/// the total size *after* fully materializing it.
class _BoundedByteSink implements Sink<List<int>> {
  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  bool overflowed = false;

  _BoundedByteSink(this.maxBytes);

  @override
  void add(List<int> chunk) {
    // Once flagged, stop accumulating — the caller stops feeding input too,
    // but a chunk already in flight when that happens must not still grow
    // an already-abandoned buffer.
    if (overflowed) return;
    _builder.add(chunk);
    if (_builder.length > maxBytes) overflowed = true;
  }

  @override
  void close() {}

  Uint8List get bytes => _builder.toBytes();
}

/// Decompresses [bytes] if they're gzip (magic number `1F 8B`), otherwise
/// returns them unchanged. A plain-JSON legacy backup always starts with
/// `{` (`0x7B`) or whitespace — never these two bytes — so this check is
/// unambiguous and doesn't depend on the picked file's extension.
///
/// Feeds the input through [GZipCodec.decoder]'s chunked conversion API in
/// pieces, rather than `gzip.decode` on it all at once, so a decompression
/// bomb is caught by [_BoundedByteSink] and aborted partway through instead
/// of first allocating its full size. The overflow check runs *before* each
/// chunk, so [BackupTooLargeException] is always thrown deliberately —
/// never by catching a byproduct exception from the codec itself, which is
/// reserved for a genuinely malformed stream ([BackupCorruptedException]).
@visibleForTesting
List<int> decompressIfGzipped(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    const chunkSize = 64 * 1024;
    final sink = _BoundedByteSink(_kMaxDecompressedBackupBytes);
    final input = gzip.decoder.startChunkedConversion(sink);
    try {
      for (var i = 0; i < bytes.length; i += chunkSize) {
        if (sink.overflowed) throw const BackupTooLargeException();
        final end = (i + chunkSize).clamp(0, bytes.length);
        input.add(bytes.sublist(i, end));
      }
      input.close();
    } on BackupTooLargeException {
      rethrow;
    } catch (e) {
      // add/close reject invalid data — reclassified with a message that
      // names the actual problem, instead of propagating the codec's own
      // exception type or silently returning partial garbage.
      throw const BackupCorruptedException();
    }
    return sink.bytes;
  }
  return bytes;
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
Future<int> _countNewMatches(
  Object? rows,
  RankedHistoryStore? rankedStore,
) async {
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

  // Captured before anything runs. Covers a gap restorePrefsData's own
  // snapshot can't: it runs as the *last* step inside importBackupData's
  // transaction, so it can finish writing every key — its own snapshot now
  // out of scope — and only then have the transaction's commit fail,
  // leaving prefs changed under rolled-back database rows. Harmless overlap
  // with an ordinary restorePrefsData failure, which already restores
  // prefs correctly before this would even run.
  final outerSnapshot = _PrefsSnapshot.capture(
    prefs,
    prefsKeysTouchedByRestore(prefs, prefsData),
  );

  try {
    // Database rows first, prefs last - a malformed file should fail before
    // any pref commits, not after. When there's DB data, restorePrefsData
    // runs *inside* importBackupData's own transaction (see its doc), so a
    // failure on either side rolls back both. Without DB data (a prefs-only
    // v1 file, or no rankedStore), restorePrefsData's own internal rollback
    // is already atomic on its own.
    final rankedHistory = envelope['ranked_history']; // absent in v1
    final statSnapshots =
        envelope['stat_snapshots']; // absent in v1/v2 (rode along in prefs)
    final hasDbData =
        rankedStore != null && (rankedHistory is List || statSnapshots is List);

    if (hasDbData) {
      final matchRows = rankedHistory is List ? rankedHistory : const [];
      final snapshotRows = statSnapshots is List ? statSnapshots : const [];
      await rankedStore.importBackupData(
        matchRows: matchRows,
        snapshotRows: snapshotRows,
        restorePrefs: () => restorePrefsData(prefs, prefsData),
      );
      if (matchRows.isNotEmpty) {
        log.i('Backup restored ${matchRows.length} ranked matches');
      }
      if (snapshotRows.isNotEmpty) {
        log.i('Backup restored ${snapshotRows.length} RP snapshots');
      }
    } else {
      await restorePrefsData(prefs, prefsData);
    }

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
    // The database half is transactional, restorePrefsData rolls back its
    // own failures, and outerSnapshot covers the gap between them (see its
    // doc) — so this should leave the device as it was. Still say so rather
    // than assert it, since rollback is itself only best-effort.
    await outerSnapshot.rollback();
    return ImportError(
      'Failed to restore the backup file. Your existing data should be '
      'unaffected; if something looks wrong, try restoring the backup again.',
    );
  }
}
