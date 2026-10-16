import 'package:apexlytics/models/map_rotation.dart';
import 'package:apexlytics/screens/home/widgets/map_rotation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatNextMapEnd', () {
    // 14:00, a fixed local time so the clock never matters.
    final now = DateTime(2026, 10, 15, 14);

    test(
      'is the current map\'s remaining time plus the next map\'s length',
      () {
        // 30 min left, then a 60-minute map: it ends 90 minutes from now.
        expect(
          formatNextMapEnd(remainingSecs: 30 * 60, durationMins: 60, now: now),
          '3:30 PM',
        );
      },
    );

    test('names the day when the next map ends after midnight', () {
      expect(
        formatNextMapEnd(remainingSecs: 9 * 3600, durationMins: 120, now: now),
        '1:00 AM tomorrow',
      );
    });

    test('is absent when the API gave the next map no length', () {
      // A guessed time is worse than none.
      expect(
        formatNextMapEnd(remainingSecs: 1800, durationMins: 0, now: now),
        isNull,
      );
    });
  });

  group('the Up Next row', () {
    MapMode mode(String map, {int remaining = 0, int minutes = 0}) => MapMode(
      map: map,
      remainingSecs: remaining,
      durationMins: minutes,
      asset: '',
    );

    Future<void> pump(WidgetTester tester, {required int nextMinutes}) {
      final rotation = MapRotation(
        battleRoyaleCurrent: mode('Olympus', remaining: 1800, minutes: 60),
        battleRoyaleNext: mode("World's Edge", minutes: nextMinutes),
        rankedCurrent: mode('Olympus', remaining: 1800, minutes: 60),
        rankedNext: mode("World's Edge", minutes: nextMinutes),
      );
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MapRotationCard(rotation: rotation)),
        ),
      );
    }

    testWidgets('shows when the next map starts and when it ends', (
      tester,
    ) async {
      await pump(tester, nextMinutes: 60);

      expect(
        find.textContaining(RegExp(r'^Starts at \d{1,2}:\d{2} [AP]M$')),
        findsOneWidget,
      );
      expect(
        find.textContaining(RegExp(r'^Ends at \d{1,2}:\d{2} [AP]M')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows only the start time when the length is unknown', (
      tester,
    ) async {
      await pump(tester, nextMinutes: 0);

      expect(find.textContaining('Starts at'), findsOneWidget);
      expect(find.textContaining('Ends at'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
