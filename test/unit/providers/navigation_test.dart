import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexlytics/providers/navigation_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> containerWithProfile({
  required bool hasProfile,
}) async {
  SharedPreferences.setMockInitialValues(
    hasProfile
        ? {
            'player_profiles':
                '[{"name":"Aceu","uid":"1006838015507","platform":"PC"}]',
          }
        : <String, Object>{},
  );
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('appTabForDefault', () {
    test('maps legacy defaultTab indices to stable identities', () {
      expect(appTabForDefault(0), AppTab.home);
      expect(appTabForDefault(1), AppTab.stats);
      expect(appTabForDefault(2), AppTab.search);
      expect(appTabForDefault(3), AppTab.settings);
    });

    test('falls back to Home for out-of-range values', () {
      expect(appTabForDefault(99), AppTab.home);
      expect(appTabForDefault(-1), AppTab.home);
    });
  });

  group('visibleTabsProvider', () {
    test('is a fixed 4-tab set regardless of profile state', () async {
      final withProfile = await containerWithProfile(hasProfile: true);
      addTearDown(withProfile.dispose);
      final withoutProfile = await containerWithProfile(hasProfile: false);
      addTearDown(withoutProfile.dispose);

      const expected = [
        AppTab.home,
        AppTab.stats,
        AppTab.search,
        AppTab.settings,
      ];
      expect(withProfile.read(visibleTabsProvider), expected);
      expect(withoutProfile.read(visibleTabsProvider), expected);
    });
  });
}
