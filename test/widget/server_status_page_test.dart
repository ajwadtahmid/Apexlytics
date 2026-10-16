import 'package:apexlytics/models/server_status.dart';
import 'package:apexlytics/screens/home/server_status_page.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/status_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ServerStatus statusOf(Map<String, Map<String, Object>> regions) =>
    ServerStatus.fromJson({'EA_accounts': regions});

void main() {
  Future<void> pump(WidgetTester tester, ServerStatus status) =>
      tester.pumpWidget(MaterialApp(home: ServerStatusPage(status: status)));

  // The region dots, which are the small ones.
  Iterable<Color> regionDots(WidgetTester tester) => tester
      .widgetList<StatusDot>(find.byType(StatusDot))
      .where((d) => d.size == 6)
      .map((d) => d.color);

  testWidgets('a region that is down is red with no reading, not a green '
      '0ms', (tester) async {
    await pump(
      tester,
      statusOf({
        'EU-West': {'Status': 'DOWN', 'ResponseTime': 0, 'HTTPCode': 0},
        'US-East': {'Status': 'UP', 'ResponseTime': 20, 'HTTPCode': 200},
      }),
    );

    expect(find.text('EU-West | —'), findsOneWidget);
    expect(find.text('EU-West | 0ms'), findsNothing);
    expect(regionDots(tester), [AppTheme.red, AppTheme.green]);
  });

  testWidgets('a region that is up is coloured by its latency', (tester) async {
    await pump(
      tester,
      statusOf({
        'US-East': {'Status': 'UP', 'ResponseTime': 120, 'HTTPCode': 200},
        'EU-West': {'Status': 'UP', 'ResponseTime': 400, 'HTTPCode': 200},
      }),
    );

    expect(find.text('US-East | 120ms'), findsOneWidget);
    expect(regionDots(tester), [AppTheme.orange, AppTheme.red]);
  });

  testWidgets('an unrecognised status is shown as it came, not as UP', (
    tester,
  ) async {
    await pump(
      tester,
      statusOf({
        'EU-West': {'Status': 'MAINTENANCE', 'ResponseTime': 30},
      }),
    );

    expect(find.text('MAINTENANCE'), findsOneWidget);
    expect(find.text('UP'), findsNothing);
    expect(regionDots(tester), [AppTheme.muted]);
  });
}
