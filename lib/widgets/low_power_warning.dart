import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/low_power_provider.dart';
import '../utils/theme.dart';

/// Warns that "Keep screen on" can't work in iOS Low Power Mode. Hidden unless
/// [lowPowerWarningProvider] holds. [dismissible] makes it a closable banner
/// (Home, Stats); otherwise it sits inline under the setting.
class LowPowerWarning extends ConsumerWidget {
  final bool dismissible;
  const LowPowerWarning({super.key, this.dismissible = false});

  static const _message =
      'Low Power Mode is on. iOS then turns the screen off after 30 seconds, '
      "so Keep screen on can't work, and history isn't recorded while the "
      'screen is off. Turn Low Power Mode off while you play.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(lowPowerWarningProvider)) return const SizedBox.shrink();
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
            const Expanded(
              child: Text(
                _message,
                style: TextStyle(color: AppTheme.accent2, fontSize: 12),
              ),
            ),
            if (dismissible)
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                onTap: ref.read(lowPowerBannerDismissedProvider.notifier).dismiss,
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
