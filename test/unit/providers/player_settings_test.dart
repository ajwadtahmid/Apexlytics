import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/providers/settings_provider.dart';

/// Builds a [ProviderContainer] backed by an in-memory [SharedPreferences].
Future<ProviderContainer> makeContainer([
  Map<String, Object> initialPrefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('PlayerSettingsNotifier', () {
    test('initial state has no player set', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      expect(container.read(playerSettingsProvider).isPlayerSet, isFalse);
    });

    test('setPlayer persists name, uid, and platform', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container
          .read(playerSettingsProvider.notifier)
          .setPlayer('Aceu', 'uid999', 'PC');

      final settings = container.read(playerSettingsProvider);
      expect(settings.name, 'Aceu');
      expect(settings.uid, 'uid999');
      expect(settings.platform, 'PC');
      expect(settings.isPlayerSet, isTrue);
    });

    test('setPlayer updates existing profile', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container
          .read(playerSettingsProvider.notifier)
          .setPlayer('Old', 'uid1', 'PS4');
      await container
          .read(playerSettingsProvider.notifier)
          .setPlayer('New', 'uid2', 'PC');

      final settings = container.read(playerSettingsProvider);
      expect(settings.name, 'New');
      expect(settings.uid, 'uid2');
    });

    test('setDefaultTab updates and persists tab index', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(playerSettingsProvider.notifier).setDefaultTab(2);

      expect(container.read(playerSettingsProvider).defaultTab, 2);
    });

    test('setStatsRefreshMinutes updates value', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container
          .read(playerSettingsProvider.notifier)
          .setStatsRefreshMinutes(30);

      expect(container.read(playerSettingsProvider).statsRefreshMinutes, 30);
    });

    test('setCompactLegendCards toggles value', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container
          .read(playerSettingsProvider.notifier)
          .setCompactLegendCards(true);

      expect(container.read(playerSettingsProvider).compactLegendCards, isTrue);
    });

    test('state is loaded from pre-existing prefs', () async {
      // Simulate pre-existing SharedPreferences (e.g. after app restart).
      final container = await makeContainer({'default_tab': 3});
      addTearDown(container.dispose);

      expect(container.read(playerSettingsProvider).defaultTab, 3);
    });

    test('profiles list starts empty', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      expect(container.read(playerSettingsProvider).profiles, isEmpty);
    });

    test('activeProfile is null when no profiles exist', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      expect(container.read(playerSettingsProvider).activeProfile, isNull);
    });

    test('clear() resets UI prefs (defaultTab, statsRefreshMinutes, compactLegendCards)',
        () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(playerSettingsProvider.notifier);

      await notifier.setDefaultTab(2);
      await notifier.setStatsRefreshMinutes(30);
      await notifier.setCompactLegendCards(true);
      await notifier.clear();

      final settings = container.read(playerSettingsProvider);
      expect(settings.defaultTab, 0);
      expect(settings.statsRefreshMinutes, 0);
      expect(settings.compactLegendCards, isFalse);

      // Reload from prefs to confirm the keys were actually removed, not
      // just reset in memory.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('default_tab'), isNull);
      expect(prefs.getInt('stats_refresh_minutes'), isNull);
      expect(prefs.getBool('compact_legend_cards'), isNull);
    });
  });
}
