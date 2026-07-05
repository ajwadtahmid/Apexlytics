import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/utils/storage/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('backup key allowlist', () {
    // Every map-rotation notification setting a user can configure. If a new
    // alert category is added, its toggle + minutes keys belong here AND in the
    // backup allowlist — this test fails until both are wired, so a category
    // can't silently escape backup/restore (the Wildcard regression).
    const notificationKeys = <String>[
      PrefsKeys.notifyPubsMapRotation,
      PrefsKeys.notifyRankedMapRotation,
      PrefsKeys.notifyMixtapeMapRotation,
      PrefsKeys.notifyWildcardMapRotation,
      PrefsKeys.pubsNotifyMinutes,
      PrefsKeys.rankedNotifyMinutes,
      PrefsKeys.mixtapeNotifyMinutes,
      PrefsKeys.wildcardNotifyMinutes,
    ];

    for (final key in notificationKeys) {
      test('"$key" is included in backups', () {
        expect(backupIncludesKey(key), isTrue);
      });
    }

    test('Wildcard notification settings are backup-included', () {
      // The exact keys H-1 found missing — kept as an explicit guard.
      expect(backupIncludesKey(PrefsKeys.notifyWildcardMapRotation), isTrue);
      expect(backupIncludesKey(PrefsKeys.wildcardNotifyMinutes), isTrue);
    });

    test('runtime caches and one-shot flags are excluded from backups', () {
      // Server-derived / device-local state must not travel between devices.
      expect(backupIncludesKey(PrefsKeys.approvedUidsCache), isFalse);
      expect(backupIncludesKey(PrefsKeys.uidSearchWarningShown), isFalse);
      expect(backupIncludesKey(PrefsKeys.onboardingVersion), isFalse);
      expect(backupIncludesKey('api_cache:whatever'), isFalse);
    });
  });

  group('restorePrefsData', () {
    test('restores a native string-list value instead of dropping it', () async {
      // Every backed-up list pref today is stored as a JSON-encoded string, so
      // this simulates the type a future setStringList-backed pref would
      // round-trip as — the exact case that used to hit the "unsupported
      // type" branch and vanish silently.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await restorePrefsData(prefs, {
        PrefsKeys.favoriteRankedMapNames: ['Olympus', "World's Edge"],
      });

      expect(
        prefs.getStringList(PrefsKeys.favoriteRankedMapNames),
        ['Olympus', "World's Edge"],
      );
    });

    test('still restores string/int/bool/double values', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await restorePrefsData(prefs, {
        PrefsKeys.playerName: 'Aceu',
        PrefsKeys.statsRefreshMinutes: 30,
        PrefsKeys.compactLegendCards: true,
      });

      expect(prefs.getString(PrefsKeys.playerName), 'Aceu');
      expect(prefs.getInt(PrefsKeys.statsRefreshMinutes), 30);
      expect(prefs.getBool(PrefsKeys.compactLegendCards), isTrue);
    });

    test('skips keys not on the backup allowlist', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await restorePrefsData(prefs, {
        PrefsKeys.uidSearchWarningShown: true,
        'api_cache:whatever': 'stale',
      });

      expect(prefs.getBool(PrefsKeys.uidSearchWarningShown), isNull);
      expect(prefs.getString('api_cache:whatever'), isNull);
    });
  });
}
