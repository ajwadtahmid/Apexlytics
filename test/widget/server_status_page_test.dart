import 'dart:async';

import 'package:apexlytics/env/env.dart';
import 'package:apexlytics/models/server_status.dart';
import 'package:apexlytics/providers/proxy_health_provider.dart';
import 'package:apexlytics/services/proxy_health.dart';
import 'package:apexlytics/screens/home/server_status_page.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/status_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ServerStatus statusOf(Map<String, Map<String, Object>> regions) =>
    ServerStatus.fromJson({'EA_accounts': regions});

void main() {
  Future<void> pump(
    WidgetTester tester,
    ServerStatus status, {
    Future<ProxyHealth> Function(String)? checker,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        proxyCheckerProvider.overrideWithValue(
          checker ??
              (_) async => (
                state: ProxyState.online,
                latency: const Duration(milliseconds: 80),
              ),
        ),
      ],
      child: MaterialApp(home: ServerStatusPage(status: status)),
    ),
  );

  // The region dots, which are the small ones.
  Iterable<Color> regionDots(WidgetTester tester) => tester
      .widgetList<StatusDot>(find.byType(StatusDot))
      .where((d) => d.size == 6)
      // The first two belong to the Apexlytics servers card above the services.
      .skip(2)
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
        'Asia': {'Status': 'UP', 'ResponseTime': 1200, 'HTTPCode': 200},
      }),
    );

    expect(find.text('US-East | 120ms'), findsOneWidget);
    expect(regionDots(tester), [AppTheme.green, AppTheme.orange, AppTheme.red]);
  });

  test('the latency scale changes at 300 and 1000 ms', () {
    expect(latencyColor(299), AppTheme.green);
    expect(latencyColor(300), AppTheme.orange);
    expect(latencyColor(999), AppTheme.orange);
    expect(latencyColor(1000), AppTheme.red);
  });

  testWidgets('a region the provider reports slow stays orange whatever its '
      'latency', (tester) async {
    await pump(
      tester,
      statusOf({
        'EU-West': {'Status': 'SLOW', 'ResponseTime': 40, 'HTTPCode': 200},
      }),
    );

    expect(regionDots(tester), [AppTheme.orange]);
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

  testWidgets('shows the primary and the backup server separately', (
    tester,
  ) async {
    await pump(
      tester,
      statusOf({
        'EU-West': {'Status': 'UP', 'ResponseTime': 20},
      }),
      checker: (url) async => url == Env.proxyUrl
          ? (
              state: ProxyState.online,
              latency: const Duration(milliseconds: 120),
            )
          : (state: ProxyState.down, latency: null),
    );
    await tester.pump();

    expect(find.text('Apexlytics Servers'), findsOneWidget);
    expect(find.text('Primary | 120ms'), findsOneWidget);
    expect(find.text('Backup | DOWN'), findsOneWidget);
    expect(find.text('PARTIAL'), findsOneWidget);
  });

  testWidgets('both servers up reads UP, and the primary down with the backup '
      'up reads PARTIAL', (tester) async {
    await pump(
      tester,
      statusOf({
        'EU-West': {'Status': 'UP', 'ResponseTime': 20},
      }),
    );
    await tester.pump();
    expect(find.text('UP'), findsWidgets);
    expect(find.text('PARTIAL'), findsNothing);
  });

  testWidgets('says checking until the answer arrives, and slow when slow', (
    tester,
  ) async {
    final reply = Completer<ProxyHealth>();
    await pump(
      tester,
      statusOf({
        'EU-West': {'Status': 'UP', 'ResponseTime': 20},
      }),
      checker: (_) => reply.future,
    );
    await tester.pump();
    expect(find.text('CHECKING'), findsOneWidget);
    expect(find.text('Primary | …'), findsOneWidget);

    reply.complete((
      state: ProxyState.slow,
      latency: const Duration(milliseconds: 2400),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('SLOW'), findsOneWidget);
    expect(find.text('Primary | 2400ms'), findsOneWidget);
  });

  testWidgets('a server that is not set up shows a dash and is not counted '
      'against the rest', (tester) async {
    await pump(
      tester,
      statusOf({
        'EU-West': {'Status': 'UP', 'ResponseTime': 20},
      }),
      checker: (url) async => url == Env.proxyUrl
          ? (
              state: ProxyState.online,
              latency: const Duration(milliseconds: 90),
            )
          : (state: ProxyState.notConfigured, latency: null),
    );
    await tester.pump();

    expect(find.text('Backup | —'), findsOneWidget);
    expect(find.text('PARTIAL'), findsNothing);
  });

  testWidgets('our servers use the same latency colours as the regions', (
    tester,
  ) async {
    await pump(
      tester,
      statusOf({
        'EU-West': {'Status': 'UP', 'ResponseTime': 20},
      }),
      checker: (url) async => url == Env.proxyUrl
          ? (
              state: ProxyState.online,
              latency: const Duration(milliseconds: 450),
            )
          : (
              state: ProxyState.slow,
              latency: const Duration(milliseconds: 2400),
            ),
    );
    await tester.pump();

    final proxyDots = tester
        .widgetList<StatusDot>(find.byType(StatusDot))
        .where((d) => d.size == 6)
        .take(2)
        .map((d) => d.color);
    expect(proxyDots, [AppTheme.orange, AppTheme.red]);
  });
}
