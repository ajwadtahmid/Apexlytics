import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/widgets/legend_header.dart';
import 'package:apexlytics/widgets/legend_trackers_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    LegendStat legend, {
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLegendTrackersSheet(context, legend),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  LegendTracker t(String name, int value) =>
      buildTracker(key: name.toLowerCase(), displayName: name, value: value);

  LegendStat loba(List<LegendTracker> trackers) =>
      buildLegend(name: 'Loba', trackers: trackers);

  testWidgets('has the legend\'s header, with its role', (tester) async {
    await open(tester, loba([t('BR Kills', 19353)]));

    expect(find.byType(LegendHeader), findsOneWidget);
    expect(find.text('Loba'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
  });

  testWidgets('lists every tracker the legend has, not just the first few', (
    tester,
  ) async {
    await open(
      tester,
      loba([
        t('BR Kills', 19353),
        t('BR Damage', 4000000),
        t('BR Executions', 310),
        t('Eye: Enemies scanned', 123405),
        t('BR Season 1 Kills', 25),
        t('BR Season 3 Wins', 0),
      ]),
    );

    expect(find.text('Trackers'), findsOneWidget);
    for (final label in [
      'BR Kills',
      'BR Damage',
      'BR Executions',
      'Eye: Enemies scanned',
      'BR Season 1 Kills',
      'BR Season 3 Wins',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('19,353'), findsOneWidget);
    expect(find.text('123,405'), findsOneWidget);
  });

  testWidgets('shows what can be worked out, as tiles', (tester) async {
    await open(
      tester,
      loba([
        t('BR Kills', 1000),
        t('BR Damage', 250000),
        t('BR Wins', 50),
        t('BR Games Played', 400),
      ]),
    );

    expect(find.text('Stats'), findsOneWidget);
    expect(find.text('Damage per Kill'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('Win Rate'), findsOneWidget);
    expect(find.text('12.5%'), findsOneWidget);
    expect(find.text('Avg Kills per Game'), findsOneWidget);
  });

  testWidgets('has no Stats section when nothing can be worked out', (
    tester,
  ) async {
    await open(tester, loba([t('BR Kills', 100)]));

    expect(find.text('Stats'), findsNothing);
    expect(find.text('Damage per Kill'), findsNothing);
    expect(find.text('Top Weapon Categories'), findsNothing);
  });

  testWidgets('ranks the top weapon types', (tester) async {
    await open(
      tester,
      loba([
        t('BR Kills', 100),
        t('BR SMG Kills', 40),
        t('BR Sniper Kills', 90),
        t('BR Pistol Kills', 10),
      ]),
    );

    expect(find.text('Top Weapon Categories'), findsOneWidget);
    // Named without the BR prefix and the Kills suffix, highest first.
    expect(find.text('Sniper'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Sniper')).dy,
      lessThan(tester.getTopLeft(find.text('SMG')).dy),
    );
  });

  testWidgets('the career entry shows its trackers and no calculations', (
    tester,
  ) async {
    await open(
      tester,
      buildLegend(
        name: 'Global',
        trackers: [
          t('Career Kills', 52000),
          t('BR Kills', 1000),
          t('BR Damage', 250000),
        ],
      ),
    );

    expect(find.text('Career'), findsOneWidget);
    expect(find.text('Career Kills'), findsOneWidget);
    expect(find.text('Stats'), findsNothing);
    expect(find.text('Damage per Kill'), findsNothing);
  });

  testWidgets('a long list scrolls instead of overflowing', (tester) async {
    await open(tester, loba([for (var i = 0; i < 60; i++) t('Tracker $i', i)]));

    expect(tester.takeException(), isNull);
    expect(find.text('Tracker 0'), findsOneWidget);
    // The end of the list is off screen until scrolled to.
    expect(find.text('Tracker 59').hitTestable(), findsNothing);

    await tester.dragUntilVisible(
      find.text('Tracker 59'),
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );

    expect(find.text('Tracker 59').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps a long name on one line at a large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const name = 'Extraordinarily Long Name';
    await open(
      tester,
      buildLegend(name: name, trackers: [t('BR Kills', 1)]),
      textScale: 2,
    );

    // One line is about 20 * 2 * 1.2 tall; two would be double that.
    expect(tester.getSize(find.text(name)).height, lessThan(60));
    // And it is scaled down to fit inside the sheet.
    expect(
      tester.getRect(find.text(name)).right,
      lessThanOrEqualTo(tester.getRect(find.byType(LegendTrackersSheet)).right),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('is only as tall as its content when short', (tester) async {
    await open(tester, loba([t('BR Kills', 100)]));

    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getSize(find.byType(LegendTrackersSheet)).height,
      lessThan(screen * 0.6),
    );
  });

  testWidgets('has no info button, the page it opens from has one', (
    tester,
  ) async {
    await open(tester, loba([t('BR Kills', 100)]));

    expect(find.byTooltip('Tracker info'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });
}
