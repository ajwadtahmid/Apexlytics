import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/utils/storage/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(backupIncludesKey('api_cache:whatever'), isFalse);
    });
  });
}
