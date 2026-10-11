import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/background_fetch_settings.dart';
import 'package:apexlytics/services/background_service.dart';

void main() {
  group('backgroundFetchIntervalFor', () {
    test('no active alert timing gets the default 30 minutes', () {
      expect(backgroundFetchIntervalFor(0), 30);
    });

    test('is raised to the 15-minute platform minimum', () {
      expect(backgroundFetchIntervalFor(5), 15);
      expect(backgroundFetchIntervalFor(10), 15);
    });

    test('follows the timing within range and is capped at an hour', () {
      expect(backgroundFetchIntervalFor(20), 20);
      expect(backgroundFetchIntervalFor(60), 60);
      expect(backgroundFetchIntervalFor(120), 60);
    });
  });

  test('stored alert settings give the interval init() starts with, not the '
      'default', () async {
    // Pubs alerts 5 minutes before: the cadence must survive a restart.
    SharedPreferences.setMockInitialValues({
      PrefsKeys.notifyPubsMapRotation: true,
      PrefsKeys.pubsNotifyMinutes: 5,
    });
    final prefs = await SharedPreferences.getInstance();

    final minutes = BackgroundFetchSettings.fromPrefs(prefs)?.minActiveMinutes;

    expect(backgroundFetchIntervalFor(minutes ?? 0), 15);
  });
}
