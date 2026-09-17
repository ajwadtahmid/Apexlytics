import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/utils/error_messages.dart';

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
          .setStatsRefreshMinutes(5);

      expect(container.read(playerSettingsProvider).statsRefreshMinutes, 5);
    });

    group('stats refresh interval', () {
      test('a fresh install inherits the 10-minute default', () async {
        final container = await makeContainer();
        addTearDown(container.dispose);

        expect(
          container.read(playerSettingsProvider).statsRefreshMinutes,
          kDefaultStatsRefreshMinutes,
        );
      });

      test('an explicit Manual choice survives the new default', () async {
        final container = await makeContainer({'stats_refresh_minutes': 0});
        addTearDown(container.dispose);

        expect(container.read(playerSettingsProvider).statsRefreshMinutes, 0);
      });

      test('a retired interval is clamped and rewritten', () async {
        final container = await makeContainer({'stats_refresh_minutes': 20});
        addTearDown(container.dispose);

        expect(container.read(playerSettingsProvider).statsRefreshMinutes, 15);

        // The clamp is persisted, so the picker highlight and the stored value
        // can't drift apart.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('stats_refresh_minutes'), 15);
      });

      test('a still-valid interval is left alone', () async {
        final container = await makeContainer({'stats_refresh_minutes': 5});
        addTearDown(container.dispose);

        expect(container.read(playerSettingsProvider).statsRefreshMinutes, 5);
      });

      test('clampStatsRefreshMinutes snaps to the nearest offered option', () {
        expect(clampStatsRefreshMinutes(0), 0);
        expect(clampStatsRefreshMinutes(20), 15);
        expect(clampStatsRefreshMinutes(30), 15);
        expect(clampStatsRefreshMinutes(7), 5);
        expect(clampStatsRefreshMinutes(8), 10);
        // Never silently downgrades an active interval to "never poll".
        expect(clampStatsRefreshMinutes(1), 5);
        expect(clampStatsRefreshMinutes(-5), 0);
        for (final option in kStatsRefreshOptions) {
          expect(clampStatsRefreshMinutes(option), option);
        }
      });
    });

    test('setCompactLegendCards toggles value', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container
          .read(playerSettingsProvider.notifier)
          .setCompactLegendCards(true);

      expect(container.read(playerSettingsProvider).compactLegendCards, isTrue);
    });

    test('setKeepScreenOn toggles value', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container
          .read(playerSettingsProvider.notifier)
          .setKeepScreenOn(true);

      expect(container.read(playerSettingsProvider).keepScreenOn, isTrue);
    });

    test('state is loaded from pre-existing prefs', () async {
      // Simulate pre-existing SharedPreferences (e.g. after app restart).
      final container = await makeContainer({'default_tab': 3});
      addTearDown(container.dispose);

      expect(container.read(playerSettingsProvider).defaultTab, 3);
    });

    group('duplicate UID guard', () {
      test('addProfile refuses a UID already saved', () async {
        final container = await makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(playerSettingsProvider.notifier);

        await notifier.addProfile('Aceu', 'uid1', 'PC');

        // Different display name and platform — the UID is the identity.
        await expectLater(
          notifier.addProfile('Renamed', 'uid1', 'PS4'),
          throwsA(isA<AppException>()),
        );
        expect(container.read(playerSettingsProvider).profiles.length, 1);
      });

      test('the refusal names the profile already holding the UID', () async {
        final container = await makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(playerSettingsProvider.notifier);

        await notifier.addProfile('Aceu', 'uid1', 'PC');

        await expectLater(
          notifier.addProfile('Renamed', 'uid1', 'PC'),
          throwsA(
            isA<AppException>().having(
              (e) => e.message,
              'message',
              contains('Aceu'),
            ),
          ),
        );
      });

      test('addProfile still accepts a distinct UID', () async {
        final container = await makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(playerSettingsProvider.notifier);

        await notifier.addProfile('Aceu', 'uid1', 'PC');
        await notifier.addProfile('Hal', 'uid2', 'PC');

        expect(container.read(playerSettingsProvider).profiles.length, 2);
      });

      test('updateProfile may keep its own UID', () async {
        final container = await makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(playerSettingsProvider.notifier);

        await notifier.addProfile('Aceu', 'uid1', 'PC');
        // A rename re-submits the same UID for the same slot — not a duplicate.
        await notifier.updateProfile(0, 'Aceu2', 'uid1', 'PC');

        expect(
          container.read(playerSettingsProvider).profiles.single.name,
          'Aceu2',
        );
      });

      test("updateProfile refuses another slot's UID", () async {
        final container = await makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(playerSettingsProvider.notifier);

        await notifier.addProfile('Aceu', 'uid1', 'PC');
        await notifier.addProfile('Hal', 'uid2', 'PC');

        await expectLater(
          notifier.updateProfile(1, 'Hal', 'uid1', 'PC'),
          throwsA(isA<AppException>()),
        );
        expect(
          container.read(playerSettingsProvider).profiles[1].uid,
          'uid2',
          reason: 'the rejected edit must not partially apply',
        );
      });

      test('setPlayer refuses a UID held by an inactive slot', () async {
        final container = await makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(playerSettingsProvider.notifier);

        await notifier.addProfile('Aceu', 'uid1', 'PC');
        await notifier.addProfile('Hal', 'uid2', 'PC');
        // Active slot is 1 (addProfile switches to the new profile); pointing it
        // at slot 0's UID would leave two slots sharing one player's data.
        await expectLater(
          notifier.setPlayer('Aceu', 'uid1', 'PC'),
          throwsA(isA<AppException>()),
        );
        expect(container.read(playerSettingsProvider).uid, 'uid2');
      });

      test(
        'setPlayer may overwrite the active slot with its own UID',
        () async {
          final container = await makeContainer();
          addTearDown(container.dispose);
          final notifier = container.read(playerSettingsProvider.notifier);

          await notifier.setPlayer('Aceu', 'uid1', 'PC');
          await notifier.setPlayer('Aceu', 'uid1', 'PS4');

          expect(container.read(playerSettingsProvider).platform, 'PS4');
          expect(container.read(playerSettingsProvider).profiles.length, 1);
        },
      );

      test('an empty UID is never treated as a duplicate', () async {
        final container = await makeContainer({
          'player_profiles': jsonEncode([
            {'name': 'Unresolved', 'uid': '', 'platform': 'PC'},
          ]),
        });
        addTearDown(container.dispose);
        final notifier = container.read(playerSettingsProvider.notifier);

        await notifier.addProfile('AlsoUnresolved', '', 'PC');

        expect(container.read(playerSettingsProvider).profiles.length, 2);
      });
    });

    group('profile cap', () {
      String profileJson(int count) => jsonEncode([
        for (var i = 0; i < count; i++)
          {'name': 'P$i', 'uid': '100000000000$i', 'platform': 'PC'},
      ]);

      test('addProfile fills up to the cap and then refuses', () async {
        final container = await makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(playerSettingsProvider.notifier);

        for (var i = 0; i < PlayerSettingsNotifier.maxProfileCount; i++) {
          await notifier.addProfile('P$i', '100000000000$i', 'PC');
        }
        expect(
          container.read(playerSettingsProvider).profiles.length,
          PlayerSettingsNotifier.maxProfileCount,
        );

        await notifier.addProfile('overflow', '1999999999999', 'PC');
        expect(
          container.read(playerSettingsProvider).profiles.length,
          PlayerSettingsNotifier.maxProfileCount,
          reason: 'the cap must hold',
        );
        expect(
          container
              .read(playerSettingsProvider)
              .profiles
              .any((p) => p.name == 'overflow'),
          isFalse,
        );
      });

      test('stored profiles beyond the cap are truncated on read', () async {
        final container = await makeContainer({
          'player_profiles': profileJson(
            PlayerSettingsNotifier.maxProfileCount + 3,
          ),
        });
        addTearDown(container.dispose);

        expect(
          container.read(playerSettingsProvider).profiles.length,
          PlayerSettingsNotifier.maxProfileCount,
        );
      });

      test('a profile set saved under the old cap of 3 still loads', () async {
        final container = await makeContainer({
          'player_profiles': profileJson(3),
        });
        addTearDown(container.dispose);

        final profiles = container.read(playerSettingsProvider).profiles;
        expect(profiles.length, 3);
        expect(profiles.first.name, 'P0');
      });
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

    test(
      'a negative stored active_profile_index is clamped to 0, not left to throw',
      () async {
        final container = await makeContainer({
          'player_profiles': jsonEncode([
            {'name': 'P0', 'uid': '1000000000000', 'platform': 'PC'},
          ]),
          PrefsKeys.activeProfileIndex: -1,
        });
        addTearDown(container.dispose);

        final settings = container.read(playerSettingsProvider);
        expect(settings.activeProfileIndex, 0);
        expect(settings.activeProfile?.name, 'P0');
      },
    );

    test('clearAll() resets UI prefs (defaultTab, statsRefreshMinutes, '
        'compactLegendCards, keepScreenOn)', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(playerSettingsProvider.notifier);

      await notifier.setDefaultTab(2);
      await notifier.setStatsRefreshMinutes(5);
      await notifier.setCompactLegendCards(true);
      await notifier.setKeepScreenOn(true);
      await notifier.clearAll();

      final settings = container.read(playerSettingsProvider);
      expect(settings.defaultTab, 0);
      // Reset to the default rather than 0: the key is removed, so the next
      // launch reads the default anyway.
      expect(settings.statsRefreshMinutes, kDefaultStatsRefreshMinutes);
      expect(settings.compactLegendCards, isFalse);
      expect(settings.keepScreenOn, isFalse);

      // Reload from prefs to confirm the keys were actually removed, not
      // just reset in memory.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('default_tab'), isNull);
      expect(prefs.getInt('stats_refresh_minutes'), isNull);
      expect(prefs.getBool('compact_legend_cards'), isNull);
      expect(prefs.getBool('keep_screen_on'), isNull);
    });

    test(
      'clearAll() removes every key except documented first-run state',
      () async {
        // One key of every shape the app persists, including the nine the old
        // enumerated clear() silently left behind.
        const uid = '1006838015507';
        final container = await makeContainer({
          PrefsKeys.profiles: '[{"name":"T","uid":"$uid","platform":"PC"}]',
          PrefsKeys.activeProfileIndex: 0,
          PrefsKeys.playerUid: uid,
          PrefsKeys.searchFavorites: '[]',
          PrefsKeys.statsRefreshMinutes: 5,
          PrefsKeys.keepScreenOn: true,
          PrefsKeys.notifyRankedMapRotation: true,
          PrefsKeys.rankedNotifyMinutes: 10,
          PrefsKeys.favoriteRankedMapNames: '["World\'s Edge"]',
          PrefsKeys.seasonHistory: '{}',
          PrefsKeys.legendVisitStack: '[]',
          PrefsKeys.snapshotKeyFor(uid): '[{"t":1,"rp":100}]',
          PrefsKeys.legendStatsKeyFor(uid): '[]',
          PrefsKeys.rankGoalKeyFor(uid): 3,
          PrefsKeys.gamesNextSync(uid): 1770000000000,
          PrefsKeys.gamesLastOutcome(uid): 'synced',
          'api_cache:/player': '{}',
          'api_cache_ts:/player': 1770000000000,
          // The documented survivors.
          PrefsKeys.onboardingVersion: 1,
          PrefsKeys.uidSearchWarningShown: true,
          PrefsKeys.rankedInfoCoachMarkShown: true,
        });
        addTearDown(container.dispose);
        await container.read(playerSettingsProvider.notifier).clearAll();

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys(),
          PlayerSettingsNotifier.survivesClearAll,
          reason: 'clearAll() must sweep every key except first-run state',
        );
      },
    );

    test('clearProfilesAndFavorites() keeps settings and history', () async {
      const uid = '1006838015507';
      final container = await makeContainer({
        PrefsKeys.profiles: '[{"name":"T","uid":"$uid","platform":"PC"}]',
        PrefsKeys.activeProfileIndex: 0,
        PrefsKeys.playerUid: uid,
        PrefsKeys.searchFavorites: '[{"query":"x","platform":"PC"}]',
        PrefsKeys.statsRefreshMinutes: 5,
        PrefsKeys.snapshotKeyFor(uid): '[{"t":1,"rp":100}]',
        PrefsKeys.rankGoalKeyFor(uid): 3,
      });
      addTearDown(container.dispose);
      await container
          .read(playerSettingsProvider.notifier)
          .clearProfilesAndFavorites();

      expect(container.read(playerSettingsProvider).profiles, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      // Identity gone...
      expect(prefs.getString(PrefsKeys.profiles), isNull);
      expect(prefs.getString(PrefsKeys.playerUid), isNull);
      expect(prefs.getString(PrefsKeys.searchFavorites), isNull);
      // ...everything else untouched. This is the whole point of the second
      // button: re-linking a profile shouldn't cost you your RP history.
      expect(prefs.getInt(PrefsKeys.statsRefreshMinutes), 5);
      expect(prefs.getString(PrefsKeys.snapshotKeyFor(uid)), isNotNull);
      expect(prefs.getInt(PrefsKeys.rankGoalKeyFor(uid)), 3);
    });

    group('removeProfile', () {
      Future<ProviderContainer> containerWithProfiles(
        List<(String, String, String)> profiles, {
        int active = 0,
      }) async {
        final container = await makeContainer();
        final notifier = container.read(playerSettingsProvider.notifier);
        for (final (name, uid, platform) in profiles) {
          await notifier.addProfile(name, uid, platform);
        }
        await notifier.setActiveProfileIndex(active);
        return container;
      }

      test(
        'removing a slot before the active one keeps the same profile active',
        () async {
          // [A, B, C] with B active. Removing A (index 0, before active index 1)
          // must shift the active pointer down so it still resolves to B, not C.
          final container = await containerWithProfiles([
            ('A', 'uidA', 'PC'),
            ('B', 'uidB', 'PC'),
            ('C', 'uidC', 'PC'),
          ], active: 1);
          addTearDown(container.dispose);
          final notifier = container.read(playerSettingsProvider.notifier);

          await notifier.removeProfile(0);

          final settings = container.read(playerSettingsProvider);
          expect(settings.profiles.map((p) => p.uid), ['uidB', 'uidC']);
          expect(settings.uid, 'uidB');
        },
      );

      test(
        'removing the active profile falls back to a neighboring slot',
        () async {
          final container = await containerWithProfiles([
            ('A', 'uidA', 'PC'),
            ('B', 'uidB', 'PC'),
            ('C', 'uidC', 'PC'),
          ], active: 1);
          addTearDown(container.dispose);
          final notifier = container.read(playerSettingsProvider.notifier);

          await notifier.removeProfile(1);

          final settings = container.read(playerSettingsProvider);
          expect(settings.profiles.map((p) => p.uid), ['uidA', 'uidC']);
          expect(settings.uid, 'uidC');
        },
      );

      test(
        'removing a slot after the active one leaves the active profile unchanged',
        () async {
          final container = await containerWithProfiles([
            ('A', 'uidA', 'PC'),
            ('B', 'uidB', 'PC'),
            ('C', 'uidC', 'PC'),
          ], active: 1);
          addTearDown(container.dispose);
          final notifier = container.read(playerSettingsProvider.notifier);

          await notifier.removeProfile(2);

          final settings = container.read(playerSettingsProvider);
          expect(settings.profiles.map((p) => p.uid), ['uidA', 'uidB']);
          expect(settings.uid, 'uidB');
        },
      );

      test(
        'removing the last remaining profile clears the active player',
        () async {
          final container = await containerWithProfiles([
            ('A', 'uidA', 'PC'),
          ], active: 0);
          addTearDown(container.dispose);
          final notifier = container.read(playerSettingsProvider.notifier);

          await notifier.removeProfile(0);

          final settings = container.read(playerSettingsProvider);
          expect(settings.profiles, isEmpty);
          expect(settings.isPlayerSet, isFalse);
        },
      );
    });
  });

  // A field omitted from equality is silent — a stale value just never
  // triggers a rebuild. One mutator per field, each proving that changing
  // only that field makes two instances compare unequal; the trailing count
  // test makes forgetting to update this list when a field is added visible
  // on review.
  group('PlayerSettings equality exhaustiveness', () {
    const base = PlayerSettings();
    final mutators = <String, PlayerSettings Function(PlayerSettings)>{
      'profiles': (s) =>
          s.copyWith(profiles: const [PlayerProfile(name: 'X', uid: '1')]),
      'activeProfileIndex': (s) => s.copyWith(activeProfileIndex: 1),
      'statsRefreshMinutes': (s) => s.copyWith(statsRefreshMinutes: 15),
      'compactLegendCards': (s) => s.copyWith(compactLegendCards: true),
      'keepScreenOn': (s) => s.copyWith(keepScreenOn: true),
      'notifyPubsMapRotation': (s) =>
          s.copyWith(notifyPubsMapRotation: true),
      'notifyRankedMapRotation': (s) =>
          s.copyWith(notifyRankedMapRotation: true),
      'notifyMixtapeMapRotation': (s) =>
          s.copyWith(notifyMixtapeMapRotation: true),
      'notifyWildcardMapRotation': (s) =>
          s.copyWith(notifyWildcardMapRotation: true),
      'rankedNotifyMinutesBefore': (s) =>
          s.copyWith(rankedNotifyMinutesBefore: 5),
      'pubsNotifyMinutesBefore': (s) =>
          s.copyWith(pubsNotifyMinutesBefore: 5),
      'mixtapeNotifyMinutesBefore': (s) =>
          s.copyWith(mixtapeNotifyMinutesBefore: 5),
      'wildcardNotifyMinutesBefore': (s) =>
          s.copyWith(wildcardNotifyMinutesBefore: 5),
      'defaultTab': (s) => s.copyWith(defaultTab: 1),
      'favoriteRankedMapNames': (s) =>
          s.copyWith(favoriteRankedMapNames: const ['Olympus']),
      'favoritePubsMapNames': (s) =>
          s.copyWith(favoritePubsMapNames: const ['Olympus']),
    };

    for (final entry in mutators.entries) {
      test('${entry.key} alone makes two instances compare unequal', () {
        final mutated = entry.value(base);
        expect(mutated, isNot(equals(base)));
        expect(mutated.hashCode, isNot(equals(base.hashCode)));
      });
    }

    test('every field on PlayerSettings has a mutator above', () {
      // Bump this alongside the map when a field is added to the class.
      expect(mutators.length, 16);
    });
  });
}
