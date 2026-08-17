import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/theme.dart';
import '../../../widgets/widgets.dart';

class StatsRefreshSection extends ConsumerWidget {
  const StatsRefreshSection({super.key});

  static const _tabOptions = [(0, 'Home'), (1, 'My Stats'), (2, 'Search'), (3, 'Settings')];

  static String _tabLabel(int tab) =>
      _tabOptions.firstWhere((t) => t.$1 == tab, orElse: () => (0, 'Home')).$2;

  static String _refreshLabel(int minutes) =>
      minutes <= 0 ? 'Manual' : 'Every $minutes min';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultTab = ref.watch(playerSettingsProvider.select((s) => s.defaultTab));
    final statsRefreshMinutes =
        ref.watch(playerSettingsProvider.select((s) => s.statsRefreshMinutes));
    final compactLegendCards =
        ref.watch(playerSettingsProvider.select((s) => s.compactLegendCards));
    final keepScreenOn =
        ref.watch(playerSettingsProvider.select((s) => s.keepScreenOn));

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
                onTap: () => _pickDefaultTab(context, ref, defaultTab),
                child: Row(
                  children: [
                    const Icon(Icons.tab_outlined, color: AppTheme.textPrimary, size: 20),
                    const SizedBox(width: AppTheme.sm),
                    const Expanded(
                      child: Text('Default tab', style: TextStyle(fontSize: 14)),
                    ),
                    Text(
                      _tabLabel(defaultTab),
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
                onTap: () => _pickRefreshInterval(context, ref, statsRefreshMinutes),
                child: Row(
                  children: [
                    const Icon(Icons.update, color: AppTheme.textPrimary, size: 20),
                    const SizedBox(width: AppTheme.sm),
                    const Expanded(
                      child: Text('Stats update frequency', style: TextStyle(fontSize: 14)),
                    ),
                    Text(
                      _refreshLabel(statsRefreshMinutes),
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
                    value: compactLegendCards,
                    onChanged: (v) =>
                        ref.read(playerSettingsProvider.notifier).setCompactLegendCards(v),
                    activeThumbColor: AppTheme.accent,
                    activeTrackColor: AppTheme.accent.withAlpha(120),
                  ),
                ],
              ),
              const Divider(color: AppTheme.surface2, height: 24),
              Row(
                children: [
                  const Icon(Icons.stay_current_portrait,
                      color: AppTheme.textPrimary, size: 20),
                  const SizedBox(width: AppTheme.sm),
                  const Expanded(
                    child: Text('Keep screen on', style: TextStyle(fontSize: 14)),
                  ),
                  Switch(
                    value: keepScreenOn,
                    onChanged: (v) =>
                        ref.read(playerSettingsProvider.notifier).setKeepScreenOn(v),
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
    // Clamping here as well as on read keeps the highlight honest even if the
    // dialog is opened before a legacy value has been rewritten.
    final currentIndex =
        kStatsRefreshOptions.indexOf(clampStatsRefreshMinutes(current));
    return _showPickerDialog(
      context: context,
      title: 'Stats update frequency',
      labels: kStatsRefreshOptions.map(_refreshLabel).toList(),
      currentIndex: currentIndex < 0 ? 0 : currentIndex,
      onSelect: (i) async {
        await ref
            .read(playerSettingsProvider.notifier)
            .setStatsRefreshMinutes(kStatsRefreshOptions[i]);
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
