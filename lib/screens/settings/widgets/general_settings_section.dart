import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../constants/api_constants.dart';
import '../../../providers/navigation_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/notifications.dart';
import '../../../utils/theme.dart';
import '../../../widgets/widgets.dart';

class GeneralSettingsSection extends ConsumerWidget {
  const GeneralSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playerSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel(label: 'Account', icon: Icons.person_outline),
        SettingsCard(
          child: settings.isPlayerSet
              ? _PlayerInfoContent(
                  settings: settings,
                  onChangeTap: () => ref.read(currentTabProvider.notifier).setTab(AppTab.stats),
                )
              : _NoPlayerContent(onTap: () => ref.read(currentTabProvider.notifier).setTab(AppTab.stats)),
        ),
      ],
    );
  }
}

class _PlayerInfoContent extends StatelessWidget {
  final PlayerSettings settings;
  final VoidCallback onChangeTap;
  const _PlayerInfoContent({required this.settings, required this.onChangeTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: onChangeTap,
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: AppTheme.accent, size: 20),
              const SizedBox(width: AppTheme.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      ApiConstants.labelFor(settings.platform),
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.muted, size: 18),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.sm),
        const Divider(color: AppTheme.surface2),
        const SizedBox(height: AppTheme.sm),
        InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: () {
            Clipboard.setData(ClipboardData(text: settings.uid));
            context.showMessage(
              'UID copied',
              duration: const Duration(seconds: 2),
            );
          },
          child: Row(
            children: [
              const Text('UID', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              const SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  settings.uid,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.sm),
              const Icon(Icons.copy, size: 14, color: AppTheme.muted),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoPlayerContent extends StatelessWidget {
  final VoidCallback onTap;
  const _NoPlayerContent({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: onTap,
      child: const Row(
        children: [
          Icon(Icons.person_outline, color: AppTheme.textPrimary, size: 20),
          SizedBox(width: AppTheme.sm),
          Expanded(
            child: Text('No player set up', style: TextStyle(color: AppTheme.textPrimary)),
          ),
          Text('Go to My Stats', style: TextStyle(color: AppTheme.accent, fontSize: 13)),
          SizedBox(width: AppTheme.xs),
          Icon(Icons.arrow_forward, color: AppTheme.accent, size: 18),
        ],
      ),
    );
  }
}
