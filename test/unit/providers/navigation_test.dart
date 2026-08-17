import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexlytics/providers/navigation_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a container whose active profile is either set or absent — the only
/// condition that now governs the Ranked tab's presence.
Future<ProviderContainer> containerWithProfile({required bool hasProfile}) async {
  SharedPreferences.setMockInitialValues(hasProfile
      ? {
          'player_profiles':
              '[{"name":"Aceu","uid":"1006838015507","platform":"PC"}]',
        }
      : <String, Object>{});
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

    test('never resolves to Ranked (not a selectable default)', () {
      for (var i = -1; i <= 5; i++) {
        expect(appTabForDefault(i), isNot(AppTab.ranked));
      }
    });
  });

  group('visibleTabsProvider', () {
    test('inserts Ranked between My Stats and Search once a profile is set',
        () async {
      final container = await containerWithProfile(hasProfile: true);
      addTearDown(container.dispose);

      final tabs = container.read(visibleTabsProvider);
      expect(tabs, [
        AppTab.home,
        AppTab.stats,
        AppTab.ranked,
        AppTab.search,
        AppTab.settings,
      ]);
      // Position matters: Ranked is the middle tab.
      expect(tabs.indexOf(AppTab.ranked), 2);
    });

    test('omits Ranked when no profile is linked yet', () async {
      final container = await containerWithProfile(hasProfile: false);
      addTearDown(container.dispose);

      final tabs = container.read(visibleTabsProvider);
      expect(tabs, [
        AppTab.home,
        AppTab.stats,
        AppTab.search,
        AppTab.settings,
      ]);
      expect(tabs.contains(AppTab.ranked), false);
      // The other tabs keep their relative order regardless of Ranked.
      expect(tabs.indexOf(AppTab.search), 2);
    });
  });
}
