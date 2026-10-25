import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/low_power_provider.dart';
import '../utils/theme.dart';

/// Warns that "Keep screen on" can't work in iOS Low Power Mode. [dismissible]
/// makes it a closable banner (Home, Stats), shown only while the Settings
/// switch for it is on ([lowPowerBannerProvider]) and with the full
/// explanation. Otherwise it is a one-line note under the setting itself, which
/// only says Low Power Mode is on ([lowPowerWarningProvider]).
class LowPowerWarning extends ConsumerWidget {
  final bool dismissible;
  const LowPowerWarning({super.key, this.dismissible = false});

  static const _short = "Low Power Mode is on. Keep screen on won't work.";

  static const _message =
      'Low Power Mode is on. iOS then turns the screen off after 30 seconds, '
      "so Keep screen on can't work, and history isn't recorded while the "
      'screen is off. Turn Low Power Mode off while you play.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(
      dismissible ? lowPowerBannerProvider : lowPowerWarningProvider,
    );
    if (!show) return const SizedBox.shrink();
    if (dismissible && ref.watch(lowPowerBannerDismissedProvider)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.md,
          vertical: AppTheme.sm,
        ),
        decoration: BoxDecoration(
          color: AppTheme.accent2.withAlpha(25),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.battery_alert_outlined,
                size: 16,
                color: AppTheme.accent2,
              ),
            ),
            const SizedBox(width: AppTheme.sm),
            Expanded(
              child: Text(
                dismissible ? _message : _short,
                style: const TextStyle(color: AppTheme.accent2, fontSize: 12),
              ),
            ),
            if (dismissible)
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                onTap: ref
                    .read(lowPowerBannerDismissedProvider.notifier)
                    .dismiss,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: AppTheme.accent2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
