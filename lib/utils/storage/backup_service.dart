import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:file_picker/file_picker.dart' show FilePicker;
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
import 'season_storage.dart' show mergeRestoredSeasonHistory;

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
  PrefsKeys.legendVisitStackPrefix,
];

bool _include(String key) {
  if (_excludedKeys.contains(key)) return false;
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

enum _PrefKind { integer, boolean, text }

const _intKeys = {
  PrefsKeys.activeProfileIndex,
  PrefsKeys.statsRefreshMinutes,
  PrefsKeys.rankedNotifyMinutes,
  PrefsKeys.pubsNotifyMinutes,
  PrefsKeys.mixtapeNotifyMinutes,
  PrefsKeys.wildcardNotifyMinutes,
  PrefsKeys.defaultTab,
};

const _boolKeys = {
  PrefsKeys.keepScreenOn,
  PrefsKeys.notifyPubsMapRotation,
  PrefsKeys.notifyRankedMapRotation,
  PrefsKeys.notifyMixtapeMapRotation,
  PrefsKeys.notifyWildcardMapRotation,
};

/// The type the app itself stores under [key]. Every other backed-up key —
/// profiles, favourites, legend stats, snapshots, season history, the per-UID
/// blobs — is a JSON-encoded string.
_PrefKind _kindOf(String key) {
  if (_intKeys.contains(key) || key.startsWith(PrefsKeys.rankGoalPrefix)) {
    return _PrefKind.integer;
  }
  if (_boolKeys.contains(key)) return _PrefKind.boolean;
  return _PrefKind.text;
}

/// [v] as the type the app stores under [key], or null when it can't be one.
///
/// A restore used to write whatever JSON type the file held. `SharedPreferences`'
/// typed getters throw a `TypeError` on a mismatch, so a hand-edited or
/// foreign file with `"keep_screen_on": 1` or `"active_profile_index": "0"`
/// made the app's root settings provider throw on every launch. A whole
/// number that arrived as a double (`30.0`) is accepted as the int it means.
@visibleForTesting
Object? coerceRestoredPref(String key, Object? v) => switch (_kindOf(key)) {
  _PrefKind.integer =>
    v is int
        ? v
        : (v is double && v.isFinite && v == v.truncateToDouble()
              ? v.toInt()
              : null),
  _PrefKind.boolean => v is bool ? v : null,
  _PrefKind.text => v is String ? v : null,
};

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
      var v = coerceRestoredPref(entry.key, entry.value);
      if (v == null) {
        log.w(
          'Backup import: skipping wrong-typed value for '
          '"${_redactUid(entry.key)}": ${entry.value.runtimeType}',
        );
        continue;
      }
      // The windows are checked and merged with what this device already
      // learned, not trusted: a bogus one would misfile matches permanently.
      if (entry.key == PrefsKeys.seasonHistory) {
        v = mergeRestoredSeasonHistory(
          backupRaw: v as String,
          deviceRaw: prefs.getString(PrefsKeys.seasonHistory),
        );
      }
      await _setTyped(prefs, entry.key, v);
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

/// Collects the gzip encoder's output.
class _ByteCollector implements Sink<List<int>> {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) => _builder.add(chunk);

  @override
  void close() {}

  List<int> get bytes => _builder.takeBytes();
}

/// The gzipped backup envelope, built page by page: the history is encoded and compressed
/// as it streams in from [matchPages], so no whole-history object or string is held and no
/// step does more than a page of work on the UI isolate. [matchCount] is the match rows written.
@visibleForTesting
Future<({List<int> bytes, int matchCount})> buildBackupBytes({
  required Map<String, Object?> prefs,
  required Stream<List<Map<String, Object?>>> matchPages,
  required Stream<List<Map<String, Object?>>> snapshotPages,
  DateTime? exportedAt,
}) async {
  final sink = _ByteCollector();
  final out = gzip.encoder.startChunkedConversion(sink);
  void write(String text) => out.add(utf8.encode(text));

  // Compact JSON (never hand-read), gzipped since it's very repetitive. The picker accepts `.gz`
  // directly, so restore stays one step via "Restore backup" (a file manager may extract it first).
  final head = jsonEncode({
    'version': _kBackupVersion,
    'exported_at': (exportedAt ?? DateTime.now()).toIso8601String(),
    'prefs': prefs,
  });
  // `head` ends in the object's closing brace; reopen it for the arrays.
  write('${head.substring(0, head.length - 1)},"ranked_history":[');
  var matchCount = 0;
  await for (final page in matchPages) {
    final json = jsonEncode(page);
    write('${matchCount == 0 ? '' : ','}${json.substring(1, json.length - 1)}');
    matchCount += page.length;
  }
  write('],"stat_snapshots":[');
  var snapshotCount = 0;
  await for (final page in snapshotPages) {
    final json = jsonEncode(page);
    write(
      '${snapshotCount == 0 ? '' : ','}${json.substring(1, json.length - 1)}',
    );
    snapshotCount += page.length;
  }
  write(']}');
  out.close();
  return (bytes: sink.bytes, matchCount: matchCount);
}

/// Whether a backup is handed to the OS share sheet instead of saved: only on
/// iOS, whose sandbox has no folder to write to (the sheet's "Save to Files"
/// covers it). Android opens the system "Save as" screen; desktop uses a
/// folder picker.
bool get backupGoesThroughShareSheet => Platform.isIOS;

/// Writes [bytes] to [file], shares it and deletes it. True only when the share
/// sheet reports the user actually completed an action; a dismissed sheet — and
/// `unavailable`, which on iOS means "couldn't tell" (e.g. another share
/// replaced this one) — is not an export, so no "saved" message follows a
/// cancel. [share] is a test seam.
@visibleForTesting
Future<bool> shareBackupFile(
  File file,
  List<int> bytes, {
  Future<ShareResult> Function(ShareParams params)? share,
}) async {
  await file.writeAsBytes(bytes);
  try {
    final result = await (share ?? SharePlus.instance.share)(
      ShareParams(files: [XFile(file.path, mimeType: 'application/gzip')]),
    );
    // The status name only (success/dismissed/unavailable): no file or player
    // data, and it shows what the platform reported if a cancel is ever
    // mistaken for an export.
    log.i('Backup share result: ${result.status.name}');
    return result.status == ShareResultStatus.success;
  } finally {
    // Don't leave the export (UIDs, names) in the temp directory.
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      log.w('Backup temp file cleanup failed', error: e);
    }
  }
}

/// Writes the backup. Android opens the system "Save as" screen; iOS the share
/// sheet ([backupGoesThroughShareSheet]); desktop writes to a folder the user
/// picks. Returns the saved file's name (never its location), or null if
/// cancelled (including a dismissed share sheet).
///
/// [rankedStore], when provided, embeds the full ranked match history in the
/// same file so device migration stays a single-file operation.
Future<String?> exportBackup(
  SharedPreferences prefs, {
  RankedHistoryStore? rankedStore,
}) async {
  final payload = _collect(prefs);
  final (bytes: compressed, :matchCount) = await buildBackupBytes(
    prefs: payload,
    matchPages: rankedStore?.exportRowPages() ?? const Stream.empty(),
    snapshotPages: rankedStore?.exportSnapshotRowPages() ?? const Stream.empty(),
  );
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final defaultFilename = 'apexlytics_$stamp.json.gz';

  if (backupGoesThroughShareSheet) {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$defaultFilename';
    final shared = await shareBackupFile(File(filePath), compressed);
    if (!shared) {
      // Dismissed: a cancellation, not an export.
      log.i('Backup share dismissed');
      return null;
    }
    // Path deliberately omitted: on desktop it can embed the OS username,
    // and log.i reaches Sentry as a breadcrumb in release builds — see the
    // privacy rule in app_logger.dart.
    log.i(
      'Backup shared: ${payload.length} keys, '
      '$matchCount ranked matches, '
      '${compressed.length} bytes compressed',
    );
    return defaultFilename;
  }

  if (Platform.isAndroid) {
    // The system "Save as" screen (the create-document picker): the user picks
    // any location, Downloads included, with the name pre-filled, and the app
    // needs no storage permission. The folder picker this replaces refuses the
    // Downloads root ("Can't use this folder") on Android 11+.
    final saved = await FilePicker.saveFile(
      fileName: defaultFilename,
      bytes: compressed is Uint8List
          ? compressed
          : Uint8List.fromList(compressed),
      mimeType: 'application/gzip',
      dialogTitle: 'Save Apexlytics backup',
    );
    if (saved == null) {
      // Cancelled: nothing was saved.
      log.i('Backup save cancelled');
      return null;
    }
    // The location is omitted for the same reason as the share branch above.
    log.i(
      'Backup saved: ${payload.length} keys, '
      '$matchCount ranked matches, '
      '${compressed.length} bytes compressed',
    );
    return savedBackupName(saved, defaultFilename);
  }

  final dirPath = await file_selector.getDirectoryPath();
  if (dirPath == null) return null;

  final filePath = [dirPath, defaultFilename].join(Platform.pathSeparator);
  await File(filePath).writeAsBytes(compressed);

  // Path omitted for the same reason as the share-sheet branch above.
  log.i(
    'Backup exported: ${payload.length} keys, '
    '$matchCount ranked matches, '
    '${compressed.length} bytes compressed',
  );
  return defaultFilename;
}

/// The file name to show for a saved backup. [saved] is whatever the picker
/// returns — a `content://` URI on Android, whose last segment looks like
/// `primary:Download/apexlytics_….json.gz` — and the user may have renamed the
/// file, so prefer the real name when it is recognisably ours, else [fallback].
@visibleForTesting
String savedBackupName(Uri saved, String fallback) {
  final last = saved.pathSegments.isEmpty ? '' : saved.pathSegments.last;
  final name = last.split(RegExp(r'[/:]')).last;
  return name.endsWith('.gz') || name.endsWith('.json') ? name : fallback;
}

// Cancellation is a PreviewResult concern now (see previewBackup) -
// commitBackupImport is only ever called after a file was already picked,
// so ImportResult itself no longer needs an ImportCancelled variant.
sealed class ImportResult {}

class ImportSuccess extends ImportResult {
  final int keyCount;

  /// Match/snapshot rows the file carried that couldn't be read and were
  /// left out, rather than failing the whole restore over them.
  final int skippedRows;

  ImportSuccess(this.keyCount, {this.skippedRows = 0});
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

  /// Names of saved profiles the backup doesn't contain. A restore replaces
  /// the profile list, so these would disappear (their history stays on disk).
  List<String> profilesReplacedBy(SharedPreferences prefs) {
    final backupUids = _profileEntries(
      (_envelope['prefs'] as Map<String, dynamic>)[PrefsKeys.profiles],
    ).map((p) => p['uid']).toSet();
    return [
      for (final p in _profileEntries(prefs.getString(PrefsKeys.profiles)))
        if (!backupUids.contains(p['uid']))
          (p['name'] as String?)?.isNotEmpty == true
              ? p['name'] as String
              : 'Unnamed profile',
    ];
  }

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

/// Decompresses and parses a picked backup for [Isolate.run]. [sizeBytes] is
/// the decompressed JSON size.
({Map<String, dynamic> envelope, int sizeBytes}) _decodeBackupEnvelope(
  Uint8List rawBytes,
) {
  final jsonBytes = decompressIfGzipped(rawBytes);
  final envelope = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
  return (envelope: envelope, sizeBytes: jsonBytes.length);
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
    // Off the UI isolate: a large backup is tens of MB of JSON.
    final (:envelope, :sizeBytes) = await Isolate.run(
      () => _decodeBackupEnvelope(rawBytes),
    );

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
        sizeBytes: sizeBytes,
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

/// The profile maps in a stored `player_profiles` string, or none.
List<Map<String, dynamic>> _profileEntries(Object? raw) {
  if (raw is! String) return const [];
  try {
    final decoded = jsonDecode(raw);
    return decoded is List
        ? decoded.whereType<Map<String, dynamic>>().toList()
        : const [];
  } catch (_) {
    return const [];
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
  // Only the ids the file carries are looked up (in chunks), so this stays
  // bounded by the file rather than by however much history is stored.
  // By the id a restore would file each row under, not the one the file claims.
  final existing = await rankedStore.existingIds([
    for (final r in rows)
      if (r is Map) ?RankedHistoryStore.canonicalIdOf(r),
  ]);
  return rows.where((r) {
    if (r is! Map) return false;
    final id = RankedHistoryStore.canonicalIdOf(r);
    return id == null || !existing.contains(id);
  }).length;
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

    var skippedRows = 0;
    if (hasDbData) {
      final matchRows = rankedHistory is List ? rankedHistory : const [];
      final snapshotRows = statSnapshots is List ? statSnapshots : const [];
      skippedRows = await rankedStore.importBackupData(
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
      if (skippedRows > 0) {
        log.w('Backup import skipped $skippedRows unreadable rows');
      }
    } else {
      await restorePrefsData(prefs, prefsData);
    }

    if (rankedStore != null) {
      // A v1/v2 file restores its snapshots as prefs keys; drain them now
      // rather than leaving the graph empty until the next launch. No-op for
      // a v3 file, which carries no legacy keys.
      //
      // Must not fail the import: rows and prefs have already committed, and the catch below
      // would roll back only prefs. The legacy keys stay for the next launch's drain.
      try {
        await migrateSnapshotsFromPrefs(prefs, rankedStore);
      } catch (e) {
        log.w(
          'Backup restore: RP snapshot drain deferred to next launch '
          '(${e.runtimeType})',
        );
      }
    }
    resetSnapshotCache();

    log.i(
      'Backup restored: ${prefsData.length} keys from v${preview.version} backup',
    );
    return ImportSuccess(prefsData.length, skippedRows: skippedRows);
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
