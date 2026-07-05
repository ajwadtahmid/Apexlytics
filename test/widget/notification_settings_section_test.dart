import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/notification_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/settings/widgets/notification_settings_section.dart';

const _bannerText = 'Notification permission off';

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, Object> prefsValues,
  required bool? permissionEnabled,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationsEnabledProvider.overrideWith(
          (ref) => permissionEnabled == null
              ? Completer<bool>().future
              : Future.value(permissionEnabled),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: NotificationSettingsSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('NotificationSettingsSection permission banner', () {
    testWidgets('shows when a mode is active but permission is off',
        (tester) async {
      await _pump(
        tester,
        prefsValues: {
          PrefsKeys.notifyRankedMapRotation: true,
          PrefsKeys.rankedNotifyMinutes: 5,
        },
        permissionEnabled: false,
      );

      expect(find.text(_bannerText), findsOneWidget);
      expect(find.text('Fix'), findsOneWidget);
    });

    testWidgets('stays hidden when every mode is off, even with permission off',
        (tester) async {
      await _pump(tester, prefsValues: {}, permissionEnabled: false);

      expect(find.text(_bannerText), findsNothing);
    });

    testWidgets('stays hidden when permission is on', (tester) async {
      await _pump(
        tester,
        prefsValues: {
          PrefsKeys.notifyRankedMapRotation: true,
          PrefsKeys.rankedNotifyMinutes: 5,
        },
        permissionEnabled: true,
      );

      expect(find.text(_bannerText), findsNothing);
    });

    testWidgets('stays hidden while the permission check is still in flight',
        (tester) async {
      await _pump(
        tester,
        prefsValues: {
          PrefsKeys.notifyRankedMapRotation: true,
          PrefsKeys.rankedNotifyMinutes: 5,
        },
        permissionEnabled: null,
      );

      expect(find.text(_bannerText), findsNothing);
    });
  });
}
