import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';

/// Whether the OS currently allows notifications — refreshed on app
/// resume/startup only (see `_AppShellState.didChangeAppLifecycleState`) so a
/// permission revoked in system settings is caught without polling.
final notificationsEnabledProvider = FutureProvider<bool>(
  (ref) => NotificationService.notificationsEnabled(),
);
