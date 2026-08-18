import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a [ProviderContainer] backed by an in-memory [SharedPreferences].
Future<ProviderContainer> makeContainer(
  Map<String, Object> initialPrefs,
) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

/// Prefs putting [uid] inside its backoff window with [outcome] recorded.
Map<String, Object> coolingDown(String uid, RankedSyncOutcome outcome) => {
  PrefsKeys.gamesNextSync(uid): DateTime.now()
      .add(const Duration(hours: 1))
      .millisecondsSinceEpoch,
  PrefsKeys.gamesLastOutcome(uid): outcome.name,
};

void main() {
  const uid = 'uid123';

  group('rankedSyncProvider inside the backoff window', () {
    // Every case here resolves without the network: the persisted deadline is
    // in the future, so the provider replays what it stored and returns.
    for (final outcome in RankedSyncOutcome.values) {
      test('replays a stored ${outcome.name} outcome', () async {
        final container = await makeContainer(coolingDown(uid, outcome));
        addTearDown(container.dispose);

        final result = await container.read(rankedSyncProvider(uid).future);

        expect(result, outcome);
      });
    }

    test('falls back to cooldown when no outcome was stored', () async {
      final container = await makeContainer({
        PrefsKeys.gamesNextSync(uid): DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      });
      addTearDown(container.dispose);

      final result = await container.read(rankedSyncProvider(uid).future);

      expect(result, RankedSyncOutcome.cooldown);
    });

    test('falls back to cooldown when the stored name is unrecognised', () async {
      final container = await makeContainer({
        PrefsKeys.gamesNextSync(uid): DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        PrefsKeys.gamesLastOutcome(uid): 'someRemovedOutcome',
      });
      addTearDown(container.dispose);

      final result = await container.read(rankedSyncProvider(uid).future);

      expect(result, RankedSyncOutcome.cooldown);
    });
  });
}
