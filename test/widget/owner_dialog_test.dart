import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/owner_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/settings/about_screen.dart';
import 'package:apexlytics/utils/storage/owner_token_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A token store that holds a token, and whose delete the platform refuses.
class _StoreThatCannotDelete implements OwnerTokenStore {
  @override
  Future<String?> read() async => 'token';

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> clear() => Future.error(StateError('keystore refused'));
}

void main() {
  Future<ProviderContainer> openOwnerDialog(
    WidgetTester tester,
    OwnerTokenStore store,
  ) async {
    SharedPreferences.setMockInitialValues({PrefsKeys.ownerUnlocked: true});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ownerTokenStoreProvider.overrideWithValue(store),
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
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('9.9.9'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a refused delete says so, keeps the token, and stays open', (
    tester,
  ) async {
    final container = await openOwnerDialog(tester, _StoreThatCannotDelete());
    expect(find.text('This device is unlocked.'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't remove the token. Try again."), findsOneWidget);
    expect(find.text('This device is unlocked.'), findsOneWidget);
    expect(container.read(ownerUnlockedProvider), isTrue);
    // And it can be tried again.
    final remove = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Remove'),
    );
    expect(remove.onPressed, isNotNull);
  });
}
