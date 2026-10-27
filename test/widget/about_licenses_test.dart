import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/settings/about_screen.dart';
import 'package:apexlytics/utils/app_license.dart';
import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app\'s own license is listed with the package licenses', () async {
    registerAppLicense();

    final entries = await LicenseRegistry.licenses.toList();
    final own = entries.where((e) => e.packages.contains('Apexlytics'));

    expect(own, isNotEmpty);
    final text = own.expand((e) => e.paragraphs).map((p) => p.text).join('\n');
    expect(text, contains('GNU GENERAL PUBLIC LICENSE'));
  });

  testWidgets('the About screen opens the licenses page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        packageInfoProvider.overrideWith(
          (ref) async => PackageInfo(
            appName: 'Apexlytics',
            packageName: 'x',
            version: '9.9.9',
            buildNumber: '1',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AboutScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.text('Open source licenses');
    await tester.scrollUntilVisible(row, 100);
    await tester.tap(row);
    // The page keeps a spinner up while it reads licenses, so settling hangs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Apexlytics'), findsWidgets);
  });
}
