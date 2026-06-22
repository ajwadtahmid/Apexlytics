import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/theme.dart';
import '../../../widgets/widgets.dart';

class StatsRefreshSection extends ConsumerWidget {
  const StatsRefreshSection({super.key});

  static const _tabOptions = [(0, 'Home'), (1, 'My Stats'), (2, 'Search'), (3, 'Settings')];
  static const _refreshOptions = [0, 10, 20, 30];

  static String _tabLabel(int tab) =>
      _tabOptions.firstWhere((t) => t.$1 == tab, orElse: () => (0, 'Home')).$2;

  static String _refreshLabel(int minutes) => switch (minutes) {
    0 => 'Manual',
    10 => 'Every 10 min',
    20 => 'Every 20 min',
    30 => 'Every 30 min',
    _ => 'Every $minutes min',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playerSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel(label: 'Preferences', icon: Icons.tune),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                onTap: () => _pickDefaultTab(context, ref, settings.defaultTab),
                child: Row(
                  children: [
                    const Icon(Icons.tab_outlined, color: AppTheme.textPrimary, size: 20),
                    const SizedBox(width: AppTheme.sm),
                    const Expanded(
                      child: Text('Default tab', style: TextStyle(fontSize: 14)),
                    ),
                    Text(
                      _tabLabel(settings.defaultTab),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 14),
                    ),
                    const SizedBox(width: AppTheme.xs),
                    const Icon(Icons.chevron_right, color: AppTheme.muted, size: 18),
                  ],
                ),
              ),
              const Divider(color: AppTheme.surface2, height: 24),
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                onTap: () => _pickRefreshInterval(context, ref, settings.statsRefreshMinutes),
                child: Row(
                  children: [
                    const Icon(Icons.update, color: AppTheme.textPrimary, size: 20),
                    const SizedBox(width: AppTheme.sm),
                    const Expanded(
                      child: Text('Stats update frequency', style: TextStyle(fontSize: 14)),
                    ),
                    Text(
                      _refreshLabel(settings.statsRefreshMinutes),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 14),
                    ),
                    const SizedBox(width: AppTheme.xs),
                    const Icon(Icons.chevron_right, color: AppTheme.muted, size: 18),
                  ],
                ),
              ),
              const Divider(color: AppTheme.surface2, height: 24),
              Row(
                children: [
                  const Icon(Icons.view_list_outlined, color: AppTheme.textPrimary, size: 20),
                  const SizedBox(width: AppTheme.sm),
                  const Expanded(
                    child: Text('Compact legend cards', style: TextStyle(fontSize: 14)),
                  ),
                  Switch(
                    value: settings.compactLegendCards,
                    onChanged: (v) =>
                        ref.read(playerSettingsProvider.notifier).setCompactLegendCards(v),
                    activeThumbColor: AppTheme.accent,
                    activeTrackColor: AppTheme.accent.withAlpha(120),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDefaultTab(BuildContext context, WidgetRef ref, int current) {
    final currentIndex = _tabOptions.indexWhere((t) => t.$1 == current);
    return _showPickerDialog(
      context: context,
      title: 'Default tab',
      labels: _tabOptions.map((t) => t.$2).toList(),
      currentIndex: currentIndex < 0 ? 0 : currentIndex,
      onSelect: (i) async {
        await ref.read(playerSettingsProvider.notifier).setDefaultTab(_tabOptions[i].$1);
      },
    );
  }

  Future<void> _pickRefreshInterval(BuildContext context, WidgetRef ref, int current) {
    final currentIndex = _refreshOptions.indexOf(current);
    return _showPickerDialog(
      context: context,
      title: 'Stats update frequency',
      labels: _refreshOptions.map(_refreshLabel).toList(),
      currentIndex: currentIndex < 0 ? 0 : currentIndex,
      onSelect: (i) async {
        await ref
            .read(playerSettingsProvider.notifier)
            .setStatsRefreshMinutes(_refreshOptions[i]);
      },
    );
  }

  static Future<void> _showPickerDialog({
    required BuildContext context,
    required String title,
    required List<String> labels,
    required int currentIndex,
    required Future<void> Function(int index) onSelect,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title),
        children: labels.asMap().entries.map((entry) {
          final selected = entry.key == currentIndex;
          return SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await onSelect(entry.key);
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color: selected ? AppTheme.accent : AppTheme.textPrimary,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (selected) const Icon(Icons.check, color: AppTheme.accent, size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
