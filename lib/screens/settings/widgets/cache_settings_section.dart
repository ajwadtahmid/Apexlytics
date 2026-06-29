import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/ranked_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/notifications.dart';
import '../../../utils/storage/backup_service.dart';
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
                icon: Icons.delete_outline,
                label: 'Clear all data',
                color: AppTheme.red,
                onTap: () => _confirm(
                  context,
                  title: 'Clear all data?',
                  body: 'All data including your linked player, favorites, and match history will be removed.',
                  onConfirm: () async {
                    await ref.read(playerSettingsProvider.notifier).clear();
                    await ref.read(searchStateProvider.notifier).clearFavorites();
                    await ref.read(rankedHistoryStoreProvider).deleteAll();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
        content: const Text(
          'This will overwrite your current data with the contents of the backup file.',
          style: TextStyle(color: AppTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Select file', style: TextStyle(color: AppTheme.accent)),
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
        context.showMessage('Backup restored ($keyCount items).');
      case ImportError(:final message):
        context.showError(message);
      case ImportCancelled():
        break;
    }
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title),
        content: Text(body, style: const TextStyle(color: AppTheme.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await onConfirm();
              } catch (e) {
                if (context.mounted) {
                  context.showError(friendlyError(e));
                }
              }
            },
            child: const Text('Confirm', style: TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
  }
}
