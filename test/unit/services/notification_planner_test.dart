import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:apexlytics/models/map_rotation.dart';
import 'package:apexlytics/services/notification_service.dart';

/// Deterministic pure-function tests for the notification scheduling math.
/// [NotificationService.projectModeSeries] takes an injected [now] and returns
/// the alerts it *would* schedule, so no platform channel is involved.
void main() {
  // tz.UTC is a built-in location and needs no database initialisation.
  final now = tz.TZDateTime.utc(2026, 6, 30, 12, 0, 0);

  MapMode mode(
    String map, {
    int remainingSecs = 600,
    int durationMins = 60,
    String? eventName,
  }) =>
      MapMode(
        map: map,
        remainingSecs: remainingSecs,
        durationMins: durationMins,
        asset: '',
        eventName: eventName,
      );

  List<PlannedAlert> project(
    MapMode next, {
    int idBase = 100,
    String label = 'Ranked',
    int remainingSecs = 600,
    int minutesBefore = 5,
    int budget = 56,
    List<String> favorites = const [],
    List<String> sequence = const [],
  }) =>
      NotificationService.projectModeSeries(
        idBase,
        label,
        next,
        remainingSecs,
        minutesBefore,
        budget,
        favoriteMapNames: favorites,
        mapSequence: sequence,
        now: now,
      );

  group('budget & per-mode caps', () {
    test('returns nothing when budget is zero or negative', () {
      expect(project(mode('WE'), budget: 0), isEmpty);
      expect(project(mode('WE'), budget: -3), isEmpty);
    });

    test('never exceeds the remaining budget', () {
      final alerts = project(
        mode('WE'),
        // 20 min remaining, 60 min cadence → many future rotations projected.
        remainingSecs: 20 * 60,
        budget: 3,
      );
      expect(alerts.length, 3);
    });

    test('caps at 12 (_maxPerMode) even with a larger budget', () {
      final alerts = project(mode('WE'), remainingSecs: 20 * 60, budget: 56);
      expect(alerts.length, 12);
    });
  });

  group('timing & ids', () {
    test('notifyAt = rotation start minus minutesBefore', () {
      final alerts = project(
        mode('WE'),
        remainingSecs: 600,
        minutesBefore: 5,
        budget: 1,
      );
      expect(alerts.first.notifyAt, now.add(const Duration(seconds: 600 - 5 * 60)));
    });

    test('drops alerts whose fire time is already in the past', () {
      // 60s remaining but we want a 5-min-before alert → fire time is behind now.
      final alerts = project(
        mode('WE', durationMins: 0), // no cadence → only the first rotation.
        remainingSecs: 60,
        minutesBefore: 5,
        budget: 5,
      );
      expect(alerts, isEmpty);
    });

    test('assigns contiguous ids from idBase', () {
      final alerts = project(
        mode('WE'),
        idBase: 100,
        remainingSecs: 20 * 60,
        budget: 3,
      );
      expect(alerts.map((a) => a.id), [100, 101, 102]);
    });
  });

  group('body copy', () {
    test('first alert uses the live map display with event name', () {
      final alerts = project(
        mode('Storm Point', eventName: 'Straight Shot'),
        budget: 1,
        minutesBefore: 5,
      );
      expect(
        alerts.first.body,
        'Ranked: Storm Point (Straight Shot) starts in 5 minutes',
      );
    });

    test('singular "minute" when minutesBefore is 1', () {
      final alerts = project(mode('WE'), budget: 1, minutesBefore: 1);
      expect(alerts.first.body, 'Ranked: WE starts in 1 minute');
    });

    test('later rotations without a sequence use generic copy', () {
      final alerts = project(
        mode('WE'),
        remainingSecs: 20 * 60,
        budget: 2,
        minutesBefore: 5,
      );
      expect(alerts[0].body, 'Ranked: WE starts in 5 minutes');
      expect(alerts[1].body, 'Ranked: Next map starts in 5 minutes');
    });
  });

  group('sequence projection', () {
    test('names future rotations by walking the cycle from nextMap', () {
      final alerts = project(
        mode('WE'),
        remainingSecs: 20 * 60,
        budget: 3,
        minutesBefore: 5,
        sequence: ['WE', 'Storm Point', 'Olympus'],
      );
      expect(alerts.map((a) => a.body), [
        'Ranked: WE starts in 5 minutes',
        'Ranked: Storm Point starts in 5 minutes',
        'Ranked: Olympus starts in 5 minutes',
      ]);
    });

    test('wraps around the sequence cyclically', () {
      final alerts = project(
        mode('Olympus'),
        remainingSecs: 20 * 60,
        budget: 3,
        minutesBefore: 5,
        sequence: ['WE', 'Storm Point', 'Olympus'],
      );
      // nextIndex=2 → i=0 Olympus, i=1 WE (wrap), i=2 Storm Point.
      expect(alerts.map((a) => a.body), [
        'Ranked: Olympus starts in 5 minutes',
        'Ranked: WE starts in 5 minutes',
        'Ranked: Storm Point starts in 5 minutes',
      ]);
    });
  });

  group('favourites filter', () {
    test('skips non-favourite rotations and only spends budget on matches', () {
      final alerts = project(
        mode('WE'),
        remainingSecs: 20 * 60,
        budget: 5,
        minutesBefore: 5,
        favorites: ['Olympus'],
        sequence: ['WE', 'Storm Point', 'Olympus'],
      );
      // Only Olympus (i=2) qualifies within the 12-rotation horizon.
      expect(alerts, isNotEmpty);
      expect(alerts.every((a) => a.body.contains('Olympus')), isTrue);
    });

    test('stops projecting once the map name is unknown while filtering', () {
      final alerts = project(
        mode('WE'),
        remainingSecs: 20 * 60,
        budget: 5,
        minutesBefore: 5,
        favorites: ['WE'],
        // no sequence → rotations past the first can't be named.
      );
      // Only the live next map (i==0) can be identified, and it is a favourite.
      expect(alerts.length, 1);
      expect(alerts.first.body, 'Ranked: WE starts in 5 minutes');
    });
  });

  group('no cadence', () {
    test('projects only the first rotation when durationMins is 0', () {
      final alerts = project(
        mode('WE', durationMins: 0),
        remainingSecs: 20 * 60,
        budget: 5,
        minutesBefore: 5,
      );
      expect(alerts.length, 1);
    });
  });
}
