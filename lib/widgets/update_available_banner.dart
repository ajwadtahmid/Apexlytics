import 'dart:async';

import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

import '../utils/theme.dart';

/// A small, dismissible strip shown when the store has a newer version than
/// the one installed. Checks the live App Store/Play Store listing directly
/// (via [Upgrader.sharedInstance]) rather than anything server-hosted, so
/// there is nothing to update on release day beyond publishing the build.
///
/// Renders identically on iOS and Android — no native store dialog, just this
/// widget — and stays hidden entirely once the user dismisses it for that
/// version (re-appears only once the *next* version ships).
class UpdateAvailableBanner extends StatefulWidget {
  const UpdateAvailableBanner({super.key});

  @override
  State<UpdateAvailableBanner> createState() => _UpdateAvailableBannerState();
}

class _UpdateAvailableBannerState extends State<UpdateAvailableBanner> {
  final Upgrader _upgrader = Upgrader.sharedInstance;
  StreamSubscription<UpgraderState>? _sub;
  bool _visible = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _sub = _upgrader.stateStream.listen((_) => _refresh());
    _upgrader.initialize().then((_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _visible = _upgrader.shouldDisplayUpgrade());
  }

  Future<void> _dismiss() async {
    await _upgrader.saveIgnored();
    if (!mounted) return;
    setState(() => _dismissed = true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _dismissed) return const SizedBox.shrink();

    final version = _upgrader.currentAppStoreVersion;

    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: _upgrader.sendUserToAppStore,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.md,
            vertical: AppTheme.sm,
          ),
          decoration: BoxDecoration(
            color: AppTheme.accent.withAlpha(25),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.arrow_circle_up_outlined,
                size: 16,
                color: AppTheme.accent,
              ),
              const SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  version == null
                      ? 'A new version is available'
                      : 'Version $version is available',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                onTap: _dismiss,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: AppTheme.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
