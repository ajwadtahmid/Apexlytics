import 'package:apexlytics/screens/ranked/widgets/recap_journey_chart.dart';
import 'package:apexlytics/utils/ranked/recap_journey.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Journey journey) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RecapJourneyChart(journey: journey)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Journey journeyOf(List<int> rps) {
    final points = [for (final (i, rp) in rps.indexed) (game: i, rp: rp)];
    var peak = 0;
    for (var i = 1; i < rps.length; i++) {
      if (rps[i] > rps[peak]) peak = i;
    }
    return Journey(points: points, peakIndex: peak, games: rps.length - 1);
  }

  testWidgets('names the start and the finish with their RP', (tester) async {
    await pump(tester, journeyOf([1000, 1020, 1050, 1040]));

    expect(find.text('Start '), findsOneWidget);
    expect(find.text('1,000'), findsOneWidget);
    expect(find.text('Finish '), findsOneWidget);
    expect(find.text('1,040'), findsOneWidget);
  });

  testWidgets('names the peak when it is a point of its own', (tester) async {
    await pump(tester, journeyOf([1000, 1020, 1050, 1040]));

    expect(find.text('Peak '), findsOneWidget);
    expect(find.text('1,050'), findsOneWidget);
  });

  testWidgets('leaves the peak out when it is the finish', (tester) async {
    await pump(tester, journeyOf([1000, 1010, 1020]));

    expect(find.text('Peak '), findsNothing);
  });

  testWidgets('leaves the peak out when it is the start', (tester) async {
    await pump(tester, journeyOf([1000, 990, 980]));

    expect(find.text('Peak '), findsNothing);
  });

  testWidgets('draws a line that never moved without breaking', (tester) async {
    await pump(tester, journeyOf([1000, 1000, 1000, 1000]));

    expect(tester.takeException(), isNull);
    expect(find.text('Start '), findsOneWidget);
  });

  testWidgets('draws a single step', (tester) async {
    await pump(tester, journeyOf([1000, 1020]));

    expect(tester.takeException(), isNull);
    expect(find.text('Finish '), findsOneWidget);
  });

  testWidgets('draws a long period', (tester) async {
    await pump(
      tester,
      journeyOf([for (var i = 0; i < 120; i++) 1000 + (i % 17) * 5]),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the picture its own height at a large text size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: RecapJourneyChart(journey: journeyOf([1000, 1020, 1050, 1040])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(RecapJourneyChart)).height,
      greaterThan(140),
    );
  });
}
