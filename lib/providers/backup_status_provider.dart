import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/prefs_keys.dart';
import '../utils/backup_reminder.dart';
import 'ranked_provider.dart';
import 'settings_provider.dart';

/// When history was last exported from this device, or null if it never was.
final lastBackupProvider = NotifierProvider<LastBackupNotifier, DateTime?>(
  LastBackupNotifier.new,
);

class LastBackupNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    final ms = ref
        .read(sharedPreferencesProvider)
        .getInt(PrefsKeys.lastBackupAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Records that a backup was just exported.
  Future<void> markBackedUp([DateTime? at]) async {
    final when = at ?? DateTime.now();
    await ref
        .read(sharedPreferencesProvider)
        .setInt(PrefsKeys.lastBackupAt, when.millisecondsSinceEpoch);
    state = when;
  }
}

/// How the recorded match history stands against the last backup. Counted
/// again when a backup is made; the Settings page also asks for a fresh count
/// each time it is opened, since games are recorded while it is out of view.
final backupStatusProvider = FutureProvider.autoDispose<BackupStatus>((
  ref,
) async {
  final last = ref.watch(lastBackupProvider);
  final store = ref.watch(rankedHistoryStoreProvider);
  return BackupStatus(
    lastBackup: last,
    newGames: await store.countStartedSince(last),
    oldestGame: await store.oldestStart(),
  );
});
