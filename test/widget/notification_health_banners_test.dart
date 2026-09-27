import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apexlytics/providers/notification_provider.dart';
import 'package:apexlytics/screens/settings/widgets/notification_health_banners.dart';

const _permissionText = 'Notification permission off';
const _initFailedText = "Alerts couldn't start — try restarting the app";

Future<void> _pump(
  WidgetTester tester, {
  required bool alertsActive,
  required bool permissionEnabled,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsEnabledProvider.overrideWith(
          (ref) => Future.value(permissionEnabled),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: NotificationHealthBanners(
            alertsActive: alertsActive,
            separator: const Divider(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // NotificationService.isInitialized is always false under `flutter test`
  // (the plugin never inits) — the same state as a real init failure.
  testWidgets('warns about both failure modes while an alert is on', (
    tester,
  ) async {
    await _pump(tester, alertsActive: true, permissionEnabled: false);

    expect(find.text(_initFailedText), findsOneWidget);
    expect(find.text(_permissionText), findsOneWidget);
  });

  testWidgets('says nothing about permission when it is granted', (
    tester,
  ) async {
    await _pump(tester, alertsActive: true, permissionEnabled: true);

    expect(find.text(_permissionText), findsNothing);
  });

  testWidgets('says nothing at all while every alert is off', (tester) async {
    await _pump(tester, alertsActive: false, permissionEnabled: false);

    expect(find.text(_initFailedText), findsNothing);
    expect(find.text(_permissionText), findsNothing);
    expect(find.byType(Divider), findsNothing);
  });
}
