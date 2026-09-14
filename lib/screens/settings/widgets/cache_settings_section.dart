import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/api_provider.dart';
import '../../../providers/ranked_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/background_service.dart';
import '../../../services/notification_service.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/notifications.dart';
import '../../../utils/storage/backup_service.dart';
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
                      onConfirm: () => _clearAll(context, ref),
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

  /// Erases every persisted surface: prefs (bar first-run state), the ranked
  /// match database, and the API response cache.
  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    await ref.read(searchStateProvider.notifier).clearFavorites();
    await ref.read(playerSettingsProvider.notifier).clearAll();
    await ref.read(rankedHistoryStoreProvider).deleteAll();
    await ref.read(apiServiceProvider).clearCache();
    // clearAll() wipes every notification pref, but nothing else tears down
    // alerts already scheduled with the OS or resets the background-fetch
    // cadence — without this, up to 56 map-rotation alerts (some surviving a
    // reboot) keep firing after the user erased everything.
    await NotificationService.cancelAll();
    await BackgroundService.updateInterval(0);
    // These read through caches that deleteAll() alone won't invalidate, so
    // they'd otherwise keep serving erased data until relaunch.
    resetSnapshotCache();
    invalidatePlayerDerivedProviders(ref);
    if (context.mounted) {
      context.showMessage('All data cleared.');
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
        context.showMessage(
          'Backup saved: ${Uri.file(filePath).pathSegments.last}',
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showError('Export failed: ${friendlyError(e)}');
      }
    }
  }

  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Import backup?'),
        // "Merge" matches importRows' actual behavior: it replaces rows the
        // backup carries, leaving local-only rows untouched.
        content: const Text(
          'This will restore the backup\'s settings and profiles, and merge '
          'its match history into your current data.',
          style: TextStyle(color: AppTheme.muted),
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
            child: const Text(
              'Select file',
              style: TextStyle(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final importResult = await importBackup(
      prefs,
      rankedStore: ref.read(rankedHistoryStoreProvider),
    );

    if (!context.mounted) return;

    switch (importResult) {
      case ImportSuccess(:final keyCount):
        ref.invalidate(playerSettingsProvider);
        ref.invalidate(searchStateProvider);
        // Same UID as before restore, so these families' cached values would
        // otherwise survive and the Ranked tab would show stale data.
        invalidatePlayerDerivedProviders(ref);
        context.showMessage('Backup restored ($keyCount items).');
      case ImportError(:final message):
        context.showError(message);
      case ImportCancelled():
        break;
    }
  }

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
