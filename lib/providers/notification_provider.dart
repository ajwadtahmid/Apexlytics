import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';

/// Whether the OS currently allows notifications — refreshed on app
/// resume/startup only (see `_AppShellState.didChangeAppLifecycleState`) so a
/// permission revoked in system settings is caught without polling.
final notificationsEnabledProvider = FutureProvider<bool>(
  (ref) => NotificationService.notificationsEnabled(),
);

/// Sends the test alert shown in the map alerts sheet. A provider so tests can
/// stand in for the notification plugin, which does not exist under them.
final testAlertSenderProvider = Provider<Future<TestAlertResult> Function()>(
  (ref) => NotificationService.sendTestAlert,
);
