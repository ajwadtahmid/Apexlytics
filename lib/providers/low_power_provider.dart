import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/app_logger.dart';
import 'settings_provider.dart';

/// Keep screen on means something on a phone or tablet only. Overridden in
/// tests.
final keepScreenOnPlatformProvider = Provider<bool>(
  (_) => keepScreenOnSupported,
);

/// For code with no [Ref] to hand, such as a `dispose`.
bool get keepScreenOnSupported => Platform.isAndroid || Platform.isIOS;

/// iOS only: Low Power Mode caps Auto-Lock at 30 seconds there. Overridden in
/// tests.
final lowPowerPlatformProvider = Provider<bool>((_) => Platform.isIOS);

/// Reads whether Low Power Mode is on right now. Overridden in tests.
final lowPowerReaderProvider = Provider<Future<bool> Function()>((_) {
  final battery = Battery();
  return () => battery.isInBatterySaveMode;
});

/// iOS sends no Low Power Mode change event, so it is polled.
const _lowPowerPoll = Duration(seconds: 10);

/// Whether Low Power Mode is on: read on start, on resume and every 10 s while
/// watched. A failed read counts as off.
final lowPowerModeProvider = StreamProvider.autoDispose<bool>((ref) {
  final read = ref.watch(lowPowerReaderProvider);
  final controller = StreamController<bool>();

  Future<void> check() async {
    bool on;
    try {
      on = await read();
    } catch (e) {
      log.w('Low Power Mode read failed', error: e);
      on = false;
    }
    if (!controller.isClosed) controller.add(on);
  }

  unawaited(check());
  final timer = Timer.periodic(_lowPowerPoll, (_) => unawaited(check()));
  final lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
    unawaited(controller.close());
  });
  return controller.stream;
});

/// Whether to warn: iOS, Keep screen on, and Low Power Mode on.
final lowPowerWarningProvider = Provider.autoDispose<bool>((ref) {
  if (!ref.watch(lowPowerPlatformProvider)) return false;
  final keepScreenOn = ref.watch(
    playerSettingsProvider.select((s) => s.keepScreenOn),
  );
  if (!keepScreenOn) return false;
  return ref.watch(lowPowerModeProvider).value ?? false;
});

/// Whether to show the banner on Home and Stats: the warning above, unless the
/// user has turned the banner off in Settings. Off stays off until they turn it
/// back on.
final lowPowerBannerProvider = Provider.autoDispose<bool>((ref) {
  final enabled = ref.watch(
    playerSettingsProvider.select((s) => s.lowPowerWarning),
  );
  return enabled && ref.watch(lowPowerWarningProvider);
});

/// Whether the banner was closed this session (in memory only).
final lowPowerBannerDismissedProvider =
    NotifierProvider<LowPowerBannerDismissed, bool>(
      LowPowerBannerDismissed.new,
    );

class LowPowerBannerDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}
