import 'package:apexlytics/providers/low_power_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/settings/widgets/stats_refresh_section.dart';
import 'package:apexlytics/widgets/low_power_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const warning = 'Low Power Mode is on.';

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool ios = true,
    bool keepScreenOn = true,
    bool lowPower = true,
    bool dismissible = false,
    bool failRead = false,
    bool bannerOn = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        lowPowerPlatformProvider.overrideWithValue(ios),
        lowPowerReaderProvider.overrideWithValue(
          () async => failRead ? throw StateError('no plugin') : lowPower,
        ),
      ],
    );
    await container
        .read(playerSettingsProvider.notifier)
        .setKeepScreenOn(keepScreenOn);
    await container
        .read(playerSettingsProvider.notifier)
        .setLowPowerWarning(bannerOn);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: LowPowerWarning(dismissible: dismissible)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  // Only the container's disposal cancels the provider's poll timer.
  Future<void> unmount(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump();
  }

  testWidgets('the banner is shown on iOS with Keep screen on and Low Power '
      'Mode on, with the full explanation', (tester) async {
    final container = await pump(tester, dismissible: true);
    expect(find.textContaining(warning), findsOneWidget);
    expect(find.textContaining('30 seconds'), findsOneWidget);
    await unmount(tester, container);
  });

  testWidgets('the one in Settings is a single short line', (tester) async {
    final container = await pump(tester);
    expect(
      find.text("Low Power Mode is on. Keep screen on won't work."),
      findsOneWidget,
    );
    expect(find.textContaining('30 seconds'), findsNothing);
    await unmount(tester, container);
  });

  testWidgets('turning the banner off hides it, and only it', (tester) async {
    final banner = await pump(tester, dismissible: true, bannerOn: false);
    expect(find.textContaining(warning), findsNothing);
    await unmount(tester, banner);

    // The line in Settings still says Low Power Mode is on.
    final inline = await pump(tester, bannerOn: false);
    expect(find.textContaining(warning), findsOneWidget);
    await unmount(tester, inline);
  });

  testWidgets('turning the banner back on shows it again', (tester) async {
    final container = await pump(tester, dismissible: true, bannerOn: false);
    expect(find.textContaining(warning), findsNothing);

    await container
        .read(playerSettingsProvider.notifier)
        .setLowPowerWarning(true);
    // The Low Power Mode read starts over, so it lands a frame later.
    await tester.pump();
    await tester.pump();
    expect(find.textContaining(warning), findsOneWidget);
    await unmount(tester, container);
  });

  testWidgets('not shown off iOS, with the setting off, or with Low Power '
      'Mode off', (tester) async {
    for (final c in [
      (ios: false, keep: true, low: true),
      (ios: true, keep: false, low: true),
      (ios: true, keep: true, low: false),
    ]) {
      final container = await pump(
        tester,
        ios: c.ios,
        keepScreenOn: c.keep,
        lowPower: c.low,
      );
      expect(find.textContaining(warning), findsNothing, reason: '$c');
      await unmount(tester, container);
    }
  });

  testWidgets('a failed read counts as off, never an error', (tester) async {
    final container = await pump(tester, failRead: true);
    expect(find.textContaining(warning), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester, container);
  });

  testWidgets('the inline version has no close button', (tester) async {
    final container = await pump(tester);
    expect(find.byIcon(Icons.close), findsNothing);
    await unmount(tester, container);
  });

  testWidgets('the banner closes, and stays closed for the session', (
    tester,
  ) async {
    final container = await pump(tester, dismissible: true);
    expect(find.textContaining(warning), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.textContaining(warning), findsNothing);
    expect(container.read(lowPowerBannerDismissedProvider), isTrue);

    // Rebuilt (another screen's banner, say): still closed.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: LowPowerWarning(dismissible: true)),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining(warning), findsNothing);
    await unmount(tester, container);
  });

  testWidgets('closing the banner does not hide the inline warning', (
    tester,
  ) async {
    final container = await pump(tester);
    container.read(lowPowerBannerDismissedProvider.notifier).dismiss();
    await tester.pump();
    expect(find.textContaining(warning), findsOneWidget);
    await unmount(tester, container);
  });

  group('the Low Power Mode switch in Settings', () {
    Future<ProviderContainer> pumpSection(
      WidgetTester tester, {
      required bool ios,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          lowPowerPlatformProvider.overrideWithValue(ios),
          lowPowerReaderProvider.overrideWithValue(() async => false),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: StatsRefreshSection()),
            ),
          ),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('is there on iOS, on by default', (tester) async {
      final container = await pumpSection(tester, ios: true);

      expect(find.text('Low Power Mode banner'), findsOneWidget);
      expect(container.read(playerSettingsProvider).lowPowerWarning, isTrue);
      await unmount(tester, container);
    });

    testWidgets('is not there anywhere else', (tester) async {
      final container = await pumpSection(tester, ios: false);

      expect(find.text('Low Power Mode banner'), findsNothing);
      await unmount(tester, container);
    });

    testWidgets('turns the banner off and stays off', (tester) async {
      final container = await pumpSection(tester, ios: true);

      await tester.tap(find.byType(Switch).last);
      await tester.pump();

      expect(container.read(playerSettingsProvider).lowPowerWarning, isFalse);
      expect(
        SharedPreferences.getInstance().then(
          (p) => p.getBool('low_power_warning'),
        ),
        completion(isFalse),
      );
      await unmount(tester, container);
    });
  });
}
