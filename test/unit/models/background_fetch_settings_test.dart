import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/background_fetch_settings.dart';

/// The pure decision logic behind background fetch: whether to schedule
/// anything at all, and at what interval. This is the headless isolate's
/// only branch point that doesn't require Dio/NotificationService/a real
/// isolate to exercise.
void main() {
  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  group('BackgroundFetchSettings.fromPrefs', () {
    test('returns null when no mode is enabled', () async {
      final prefs = await prefsWith({});
      expect(BackgroundFetchSettings.fromPrefs(prefs), isNull);
    });

    test(
      'returns null when a mode is enabled but its timing is 0 (off)',
      () async {
        final prefs = await prefsWith({
          PrefsKeys.notifyRankedMapRotation: true,
          PrefsKeys.rankedNotifyMinutes: 0,
        });
        expect(BackgroundFetchSettings.fromPrefs(prefs), isNull);
      },
    );

    test('returns settings when one mode is enabled with timing', () async {
      final prefs = await prefsWith({
        PrefsKeys.notifyRankedMapRotation: true,
        PrefsKeys.rankedNotifyMinutes: 10,
      });
      final settings = BackgroundFetchSettings.fromPrefs(prefs);
      expect(settings, isNotNull);
      expect(settings!.notifyRanked, isTrue);
      expect(settings.rankedMinutesBefore, 10);
      expect(settings.notifyPubs, isFalse);
    });

    test(
      'a legacy global timing value backfills a mode with no per-mode key',
      () async {
        final prefs = await prefsWith({
          PrefsKeys.notifyPubsMapRotation: true,
          PrefsKeys.mapNotifyMinutes: 15,
        });
        final settings = BackgroundFetchSettings.fromPrefs(prefs);
        expect(settings, isNotNull);
        expect(settings!.pubsMinutesBefore, 15);
      },
    );

    test(
      'an explicit per-mode timing overrides the legacy global value',
      () async {
        final prefs = await prefsWith({
          PrefsKeys.notifyPubsMapRotation: true,
          PrefsKeys.mapNotifyMinutes: 15,
          PrefsKeys.pubsNotifyMinutes: 5,
        });
        final settings = BackgroundFetchSettings.fromPrefs(prefs);
        expect(settings!.pubsMinutesBefore, 5);
      },
    );

    test(
      'wildcard has no legacy fallback — it stays off without its own key',
      () async {
        final prefs = await prefsWith({
          PrefsKeys.notifyWildcardMapRotation: true,
          PrefsKeys.mapNotifyMinutes: 15,
        });
        expect(BackgroundFetchSettings.fromPrefs(prefs), isNull);
      },
    );

    test(
      'one enabled-but-timed-out mode does not mask another enabled mode',
      () async {
        final prefs = await prefsWith({
          PrefsKeys.notifyRankedMapRotation: true,
          PrefsKeys.rankedNotifyMinutes: 0,
          PrefsKeys.notifyPubsMapRotation: true,
          PrefsKeys.pubsNotifyMinutes: 10,
        });
        final settings = BackgroundFetchSettings.fromPrefs(prefs);
        expect(settings, isNotNull);
        expect(settings!.notifyRanked, isTrue);
        expect(settings.rankedMinutesBefore, 0);
        expect(settings.pubsMinutesBefore, 10);
      },
    );
  });

  group('BackgroundFetchSettings.minActiveMinutes', () {
    test('is the smallest timing among enabled modes', () async {
      final prefs = await prefsWith({
        PrefsKeys.notifyRankedMapRotation: true,
        PrefsKeys.rankedNotifyMinutes: 20,
        PrefsKeys.notifyPubsMapRotation: true,
        PrefsKeys.pubsNotifyMinutes: 5,
      });
      final settings = BackgroundFetchSettings.fromPrefs(prefs)!;
      expect(settings.minActiveMinutes, 5);
    });

    test('ignores a disabled mode even with a smaller timing', () async {
      final prefs = await prefsWith({
        PrefsKeys.notifyRankedMapRotation: true,
        PrefsKeys.rankedNotifyMinutes: 20,
        PrefsKeys.pubsNotifyMinutes: 5, // notifyPubs left false
      });
      final settings = BackgroundFetchSettings.fromPrefs(prefs)!;
      expect(settings.minActiveMinutes, 20);
    });
  });
}
