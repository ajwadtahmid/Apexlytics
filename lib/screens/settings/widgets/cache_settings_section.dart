import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/api_provider.dart';
import '../../../providers/owner_provider.dart';
import '../../../providers/ranked_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/background_service.dart';
import '../../../services/notification_service.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/notifications.dart';
import '../../../utils/storage/backup_service.dart';
import '../../../utils/storage/ranked_history_store.dart';
import '../../../utils/storage/rp_snapshot_storage.dart';
import '../../../utils/theme.dart';
import '../../../widgets/widgets.dart';

class CacheSettingsSection extends ConsumerWidget {
  const CacheSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel(label: 'Data', icon: Icons.storage),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ActionRow(
                icon: Icons.upload_outlined,
                label: 'Export data',
                onTap: () => _exportData(context, ref),
              ),
              const Divider(color: AppTheme.surface2, height: 24),
              ActionRow(
                icon: Icons.download_outlined,
                label: 'Import data',
                onTap: () => _importData(context, ref),
              ),
              const Divider(color: AppTheme.surface2, height: 24),
              ActionRow(
                icon: Icons.person_remove_outlined,
                label: 'Clear profiles & favorites',
                color: AppTheme.orange,
                onTap: () => _confirm(
                  context,
                  title: 'Clear profiles & favorites?',
                  body:
                      'Your saved profiles and favorite players will be '
                      'removed. Your settings, RP history and match history '
                      'are kept.',
                  confirmLabel: 'Clear',
                  confirmColor: AppTheme.orange,
                  onConfirm: () => _clearProfilesAndFavorites(context, ref),
                ),
              ),
              const Divider(color: AppTheme.surface2, height: 24),
              ActionRow(
                icon: Icons.delete_outline,
                label: 'Clear all data',
                color: AppTheme.red,
                // Two confirmations: ranked history is forward-only, so a
                // mis-tap here destroys accrual that can't be re-fetched.
                onTap: () => _confirm(
                  context,
                  title: 'Clear all data?',
                  body:
                      'Everything will be removed: your profiles, favorites, '
                      'settings, RP history and recorded match history.',
                  confirmLabel: 'Continue',
                  onConfirm: () async {
                    if (!context.mounted) return;
                    await _confirm(
                      context,
                      title: 'This cannot be undone',
                      body:
                          'Recorded match history only accrues while the app '
                          'is open, so it cannot be downloaded again. Export a '
                          'backup first if you might want it back.\n\n'
                          'Permanently erase all data?',
                      confirmLabel: 'Erase everything',
                      onConfirm: () async {
                        // Only an owner device has a token to decide on.
                        final removeOwnerToken = ref.read(ownerUnlockedProvider)
                            ? await _askRemoveOwnerToken(context)
                            : true;
                        if (removeOwnerToken == null || !context.mounted) {
                          return;
                        }
                        await _clearAll(
                          context,
                          ref,
                          removeOwnerToken: removeOwnerToken,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Drops saved profiles and favourites, keeping everything else.
  Future<void> _clearProfilesAndFavorites(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(playerSettingsProvider.notifier).clearProfilesAndFavorites();
    await ref.read(searchStateProvider.notifier).clearFavorites();
    if (context.mounted) {
      context.showMessage('Profiles & favorites cleared.');
    }
  }

  /// Third "Clear all data" question, owner devices only: true removes the owner token,
  /// false keeps it, null if dismissed.
  Future<bool?> _askRemoveOwnerToken(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Keep owner mode?'),
      content: const Text(
        'This device is unlocked as the owner. Keep the owner token so it '
        'stays unlocked after the erase, or remove it too.',
        style: TextStyle(color: AppTheme.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Remove token',
            style: TextStyle(color: AppTheme.red),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            'Keep token',
            style: TextStyle(color: AppTheme.green),
          ),
        ),
      ],
    ),
  );

  /// Erases every persisted surface: prefs (bar first-run state), the ranked
  /// match database, and the API cache. The owner token goes only if [removeOwnerToken].
  ///
  /// Every step runs even if an earlier one fails, and the message names
  /// whatever didn't clear. Match history goes first on purpose: clearing
  /// settings first and then failing on history would remove the profile
  /// that shows it while the history stayed on disk, unseen. This order
  /// fails the other way — data still visible, profile still there, and a
  /// retry finishes the job.
  Future<void> _clearAll(
    BuildContext context,
    WidgetRef ref, {
    required bool removeOwnerToken,
  }) async {
    final failed = <String>[];
    Future<void> step(String what, Future<void> Function() run) async {
      try {
        await run();
      } catch (e) {
        // The type only: a storage error's text can carry the SQL arguments
        // (a player's UID or name), and warnings reach crash reports.
        log.w('Clear all data: "$what" failed (${e.runtimeType})');
        failed.add(what);
      }
    }

    await step(
      'match & RP history',
      () => ref.read(rankedHistoryStoreProvider).deleteAll(),
    );
    await step('profiles, favorites & settings', () async {
      await ref.read(searchStateProvider.notifier).clearFavorites();
      await ref
          .read(playerSettingsProvider.notifier)
          .clearAll(keepOwnerUnlock: !removeOwnerToken);
    });
    // clearAll() only sweeps prefs; the token lives in secure storage. lock() also resets the flag.
    if (removeOwnerToken) {
      await step(
        'owner token',
        () => ref.read(ownerUnlockedProvider.notifier).lock(),
      );
    }
    await step(
      'cached responses',
      () => ref.read(apiServiceProvider).clearCache(),
    );
    // clearAll() wipes every notification pref, but nothing else tears down
    // alerts already scheduled with the OS or resets the background-fetch
    // cadence — without this, up to a dozen map-rotation alerts per enabled
    // mode (some surviving a reboot) keep firing after the user erased
    // everything.
    await step('scheduled map alerts', () async {
      await NotificationService.cancelAll();
      await BackgroundService.updateInterval(0);
    });
    // These read through caches that deleteAll() alone won't invalidate, so
    // they'd otherwise keep serving erased data until relaunch. Done even
    // after a partial failure: what did clear must stop showing.
    resetSnapshotCache();
    invalidatePlayerDerivedProviders(ref);
    if (!context.mounted) return;
    if (failed.isEmpty) {
      context.showMessage('All data cleared.');
    } else {
      context.showError(
        "Couldn't clear ${failed.join(' or ')}. Everything else was cleared "
        '— try again to finish.',
      );
    }
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final filePath = await exportBackup(
        prefs,
        rankedStore: ref.read(rankedHistoryStoreProvider),
      );
      if (filePath == null) return;

      if (context.mounted) {
        // iOS only shares the file, so say "shared".
        context.showMessage(
          'Backup ${Platform.isIOS ? 'shared' : 'saved'}: '
          '${Uri.file(filePath).pathSegments.last}',
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showError('Export failed: ${friendlyError(e)}');
      }
    }
  }

  // Picks and parses the file first, then confirms with the specific
  // contents (profile/match counts, how many matches are actually new). An
  // operation that merges two histories together irreversibly deserves more
  // than a generic "this will restore settings and profiles" dialog.
  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    final rankedStore = ref.read(rankedHistoryStoreProvider);
    final previewResult = await previewBackup(rankedStore: rankedStore);
    if (!context.mounted) return;

    switch (previewResult) {
      case PreviewCancelled():
        return;
      case PreviewError(:final message):
        context.showError(message);
      case PreviewReady(:final preview):
        await _confirmAndCommit(context, ref, preview, rankedStore);
    }
  }

  Future<void> _confirmAndCommit(
    BuildContext context,
    WidgetRef ref,
    BackupPreview preview,
    RankedHistoryStore rankedStore,
  ) async {
    final replaced = preview.profilesReplacedBy(
      ref.read(sharedPreferencesProvider),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Import backup?'),
        content: Text(
          _summarize(preview, replaced),
          style: const TextStyle(color: AppTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final importResult = await commitBackupImport(
      preview,
      prefs,
      rankedStore: rankedStore,
    );
    if (!context.mounted) return;

    switch (importResult) {
      case ImportSuccess(:final skippedRows):
        ref.invalidate(playerSettingsProvider);
        ref.invalidate(searchStateProvider);
        // Same UID as before restore, so these families' cached values would
        // otherwise survive and the Ranked tab would show stale data.
        invalidatePlayerDerivedProviders(ref);
        // Same counts the preview dialog already showed the user, not
        // ImportSuccess.keyCount — that's the number of raw SharedPreferences
        // keys restored (settings, favourites, ...), an internal bookkeeping
        // detail nobody asked about. Showing it as "N items" read as a wildly
        // wrong match/profile count and was more confusing than useful.
        context.showMessage(
          'Backup restored: ${_profilesLabel(preview.profileCount)}, '
          '${preview.matchCount} matches.'
          '${skippedRows > 0 ? ' $skippedRows unreadable ${skippedRows == 1 ? 'entry was' : 'entries were'} skipped.' : ''}',
        );
      case ImportError(:final message):
        context.showError(message);
    }
  }

  String _profilesLabel(int count) =>
      count == 1 ? '1 profile' : '$count profiles';

  // A heads-up, not a hard limit — restoring past this is still expected to
  // work fine, but it's large enough that "may take a moment" is honest.
  static const _largeBackupWarningBytes = 15 * 1024 * 1024; // 15 MB

  String _summarize(BackupPreview preview, List<String> replacedProfiles) {
    final exportedAt = preview.exportedAt;
    final profiles = _profilesLabel(preview.profileCount);
    return [
      if (exportedAt != null)
        'Exported ${DateFormat('MMM d, yyyy').format(exportedAt.toLocal())}.',
      '$profiles, ${preview.matchCount} matches '
          '(${preview.newMatchCount} new to this device).',
      if (preview.sizeBytes > _largeBackupWarningBytes)
        'This is a large backup (${_formatSize(preview.sizeBytes)}) — '
            'restoring may take a moment.',
      "This will restore the backup's settings and profiles, and merge its "
          'match history into your current data.',
      if (replacedProfiles.isNotEmpty)
        'Your saved profiles will be replaced by the backup\'s, so '
            '${replacedProfiles.join(', ')} will no longer be listed. Their '
            'match history stays on this device; re-add the player to see it '
            'again.',
    ].join('\n\n');
  }

  String _formatSize(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  /// Destructive-action dialog. [onConfirm] runs after the sheet is dismissed,
  /// and the returned future completes only once it has - so a caller can
  /// chain a second [_confirm] inside it to build a two-step confirmation.
  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
    String confirmLabel = 'Confirm',
    Color confirmColor = AppTheme.red,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title),
        content: Text(body, style: const TextStyle(color: AppTheme.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel, style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await onConfirm();
    } catch (e) {
      if (context.mounted) context.showError(friendlyError(e));
    }
  }
}
