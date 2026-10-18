import 'package:apexlytics/constants/ui_strings.dart';
import 'package:apexlytics/models/predator.dart';
import 'package:apexlytics/providers/predator_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/home/predator_page.dart';
import 'package:apexlytics/screens/home/widgets/predator_section.dart';
import 'package:apexlytics/utils/api_cache.dart' show ApiResult;
import 'package:apexlytics/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

PredatorResponse _data({int pcRp = 32608, DateTime? updated}) {
  PlatformPredator p(int rp, int n) =>
      PlatformPredator(minRp: rp, totalMastersAndPreds: n, updatedAt: updated);
  return PredatorResponse(
    rp: {
      'PC': p(pcRp, 12382),
      'PS4': p(23785, 5726),
      'X1': p(19446, 2184),
      'SWITCH': p(16000, 419),
    },
  );
}

void main() {
  group('the tile\'s line', () {
    test('is the cutoff on your platform, once you have one', () {
      expect(
        predatorTileSubtitle(_data(), platform: 'PC'),
        'PC cutoff: 32,608 RP',
      );
      expect(
        predatorTileSubtitle(_data(), platform: 'PS4'),
        'PS cutoff: 23,785 RP',
      );
      expect(
        predatorTileSubtitle(_data(), platform: 'SWITCH'),
        'Switch cutoff: 16,000 RP',
      );
    });

    test('is the total, with separators, with no player', () {
      expect(
        predatorTileSubtitle(_data()),
        '20,711 Masters & Preds across all platforms',
      );
    });

    test('falls back to the total when your platform has no reading', () {
      expect(
        predatorTileSubtitle(_data(pcRp: 0), platform: 'PC'),
        '20,711 Masters & Preds across all platforms',
      );
      expect(
        predatorTileSubtitle(PredatorResponse(rp: {}), platform: 'PC'),
        '0 Masters & Preds across all platforms',
      );
    });
  });

  group('the tile on Home', () {
    Future<ProviderContainer> pumpTile(
      WidgetTester t, {
      String? platform,
    }) async {
      final (c, _) = await prefsContainer(
        overrides: [
          predatorProvider.overrideWith((ref) async => ApiResult(_data())),
        ],
      );
      if (platform != null) {
        await c
            .read(playerSettingsProvider.notifier)
            .setPlayer('Aceu', '1000000000001', platform);
      }
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: PredatorSection())),
        ),
      );
      await t.pump();
      return c;
    }

    testWidgets('shows the cutoff of the selected profile\'s platform', (
      t,
    ) async {
      await pumpTile(t, platform: 'X1');

      expect(find.text('Xbox cutoff: 19,446 RP'), findsOneWidget);
    });

    testWidgets('follows a switch to another profile\'s platform', (t) async {
      final c = await pumpTile(t, platform: 'PC');
      expect(find.text('PC cutoff: 32,608 RP'), findsOneWidget);

      await c
          .read(playerSettingsProvider.notifier)
          .setPlayer('Aceu', '1000000000001', 'PS4');
      await t.pump();

      expect(find.text('PS cutoff: 23,785 RP'), findsOneWidget);
    });

    testWidgets('keeps the total for a guest', (t) async {
      await pumpTile(t);

      expect(
        find.text('20,711 Masters & Preds across all platforms'),
        findsOneWidget,
      );
    });

    testWidgets('opens the page with your platform marked', (t) async {
      await pumpTile(t, platform: 'X1');

      await t.tap(find.text('Pred Cutoff'));
      await t.pumpAndSettle();

      expect(find.text('YOUR PLATFORM'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('YOUR PLATFORM')).dy,
        closeTo(t.getTopLeft(find.text('XBOX')).dy, 2),
      );
    });
  });

  group('the page', () {
    Future<void> pumpPage(
      WidgetTester t, {
      String? yourPlatform,
      DateTime? updated,
    }) {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      return t.pumpWidget(
        MaterialApp(
          home: PredatorPage(
            data: _data(updated: updated),
            yourPlatform: yourPlatform,
          ),
        ),
      );
    }

    double top(WidgetTester t, String label) =>
        t.getTopLeft(find.text(label)).dy;

    testWidgets('lists platforms in their usual order for a guest', (t) async {
      await pumpPage(t);

      expect(find.text('YOUR PLATFORM'), findsNothing);
      expect(top(t, 'PC'), lessThan(top(t, 'PLAYSTATION')));
      expect(top(t, 'PLAYSTATION'), lessThan(top(t, 'XBOX')));
      expect(top(t, 'XBOX'), lessThan(top(t, 'NINTENDO SWITCH')));
    });

    testWidgets('keeps the order whichever platform is yours', (t) async {
      for (final mine in ['PC', 'PS4', 'X1', 'SWITCH']) {
        await pumpPage(t, yourPlatform: mine);

        expect(find.text('YOUR PLATFORM'), findsOneWidget);
        expect(top(t, 'PC'), lessThan(top(t, 'PLAYSTATION')));
        expect(top(t, 'PLAYSTATION'), lessThan(top(t, 'XBOX')));
        expect(top(t, 'XBOX'), lessThan(top(t, 'NINTENDO SWITCH')));
      }
    });

    testWidgets('outlines your card in orange, and no other', (t) async {
      await pumpPage(t, yourPlatform: 'X1');

      Finder card(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).border != null,
        ),
      );
      Color? outline(String label) {
        final box =
            t.widget<Container>(card(label).first).decoration! as BoxDecoration;
        return (box.border! as Border).top.color;
      }

      expect(outline('XBOX'), AppTheme.accent);
      expect(outline('PC'), isNot(AppTheme.accent));
    });

    testWidgets('says once how fresh the readings are', (t) async {
      await pumpPage(
        t,
        updated: DateTime.now().subtract(const Duration(minutes: 27)),
      );

      expect(find.text('Updated 27m ago'), findsOneWidget);
      expect(find.text('27m ago'), findsNothing);
    });

    testWidgets('keeps the explanation in a sheet behind an info button', (
      t,
    ) async {
      await pumpPage(t);
      expect(find.text(predatorPageInfo), findsNothing);

      await t.tap(find.byIcon(Icons.info_outline));
      await t.pumpAndSettle();

      expect(find.text('About the cutoff'), findsOneWidget);
      expect(find.text(predatorPageInfo), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);

      // Dismissed by a tap outside, as a bottom sheet is.
      await t.tapAt(const Offset(400, 20));
      await t.pumpAndSettle();
      expect(find.text(predatorPageInfo), findsNothing);
    });
  });
}
