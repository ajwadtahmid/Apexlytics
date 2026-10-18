import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/providers/storage_usage_provider.dart';
import 'package:apexlytics/screens/settings/widgets/cache_settings_section.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/formatting/format.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show inMemoryDatabasePath;

import '../helpers.dart';

void main() {
  setUpAll(useFfiDatabase);

  late RankedHistoryStore store;
  late ApiService api;
  late ProviderContainer container;
  var dbCounter = 0;

  /// The database works in real time, which the test's fake clock does not
  /// move: give it a moment, then let the widgets take in what came back.
  Future<void> letStorageFinish(WidgetTester t) async {
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pump();
    }
  }

  /// The Data card over [games] recorded games and [cached] saved responses.
  Future<void> pump(WidgetTester t, {int games = 0, int cached = 0}) async {
    // In memory and shared by every store opened that way: empty it first.
    store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    await t.runAsync(store.deleteAll);
    await t.runAsync(
      () => store.upsertAll('1', [
        for (var i = 0; i < games; i++)
          buildMatch(uid: '1', start: 1782090000 + i * 1000),
      ]),
    );
    final cacheStore = ApiCacheStore(
      overridePath:
          'file:data_section_cache_${dbCounter++}?mode=memory&cache=shared',
    );
    await t.runAsync(() async {
      for (var i = 0; i < cached; i++) {
        await cacheStore.upsert('/path$i', '{"n":$i,"pad":"${'x' * 500}"}', 1);
      }
      api = ApiService(cacheStore, httpClientAdapter: FakeHttpAdapter());
      // Primed in the background at construction; wait for it to land.
      for (var i = 0; i < 100 && api.cacheUsage.entries < cached; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    final (c, _) = await prefsContainer(
      overrides: [
        rankedHistoryStoreProvider.overrideWithValue(store),
        apiServiceProvider.overrideWithValue(api),
      ],
    );
    container = c;
    await container
        .read(playerSettingsProvider.notifier)
        .setPlayer('Aceu', '1000000000001', 'PC');
    // Counted for real, before the widgets ask.
    await t.runAsync(() async {
      final keep = container.listen(storageUsageProvider, (_, _) {});
      addTearDown(keep.close);
      await container.read(storageUsageProvider.future);
    });
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CacheSettingsSection()),
          ),
        ),
      ),
    );
    await t.pump();
  }

  group('formatBytes', () {
    test('uses bytes, then KB, then MB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(312), '312 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(48 * 1024 + 100), '48 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes((3.24 * 1024 * 1024).round()), '3.2 MB');
    });
  });

  group('under Export data', () {
    testWidgets('says how many games, how much space, and the last backup', (
      t,
    ) async {
      await pump(t, games: 3);

      expect(
        find.textContaining(
          RegExp(r'^3 games · \d+(\.\d)? (B|KB|MB) · Never backed up$'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('says so when there is none', (t) async {
      await pump(t);

      expect(
        find.text('No games saved yet · Never backed up'),
        findsOneWidget,
      );
    });

    testWidgets('says "1 game", not "1 games"', (t) async {
      await pump(t, games: 1);

      expect(find.textContaining('1 game ·'), findsOneWidget);
    });

    testWidgets('puts a separator in a long history', (t) async {
      await pump(t, games: 1200);

      expect(find.textContaining('1,200 games ·'), findsOneWidget);
    });

    testWidgets('has no line of its own above the rows', (t) async {
      await pump(t, games: 3);

      expect(find.byIcon(Icons.history), findsNothing);
      expect(
        t.getTopLeft(find.text('Export data')).dy,
        lessThan(t.getTopLeft(find.text('Import data')).dy),
      );
    });
  });

  group('the card', () {
    testWidgets('is Export, Import and Clear data, nothing more', (t) async {
      await pump(t, games: 3, cached: 2);

      expect(find.text('Export data'), findsOneWidget);
      expect(find.text('Import data'), findsOneWidget);
      expect(find.text('Clear data'), findsOneWidget);
      expect(find.text('Clear cached responses'), findsNothing);
      expect(find.text('Clear profiles & favorites'), findsNothing);
      expect(find.text('Clear all data'), findsNothing);
    });
  });

  group('Clear data', () {
    Future<void> openSheet(WidgetTester t) async {
      await t.tap(find.text('Clear data'));
      await t.pumpAndSettle();
    }

    testWidgets('lists the three ways to clear, mildest first', (t) async {
      await pump(t, cached: 3);
      await openSheet(t);

      expect(find.byType(BottomSheet), findsOneWidget);
      final cached = t.getTopLeft(find.text('Clear cached responses')).dy;
      final profiles = t.getTopLeft(find.text('Clear profiles & favorites')).dy;
      final all = t.getTopLeft(find.text('Clear all data')).dy;
      expect(cached, lessThan(profiles));
      expect(profiles, lessThan(all));
      expect(find.text('Saved profiles and favorite players'), findsOneWidget);
      expect(find.text('Everything, including match history'), findsOneWidget);
    });

    testWidgets('scrolls, so it fits a short screen', (t) async {
      await pump(t);
      // Wide enough for the test font, short enough to need scrolling.
      t.view.physicalSize = const Size(800, 300);
      await openSheet(t);

      expect(t.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
    });

    testWidgets('closes before it asks', (t) async {
      await pump(t, cached: 3);
      await openSheet(t);

      await t.tap(find.text('Clear profiles & favorites'));
      await t.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Clear profiles & favorites?'), findsOneWidget);
    });

    testWidgets('Clear profiles & favorites removes the profile only', (
      t,
    ) async {
      await pump(t, games: 2, cached: 3);
      await openSheet(t);

      await t.tap(find.text('Clear profiles & favorites'));
      await t.pumpAndSettle();
      await t.tap(find.text('Clear'));
      await t.pump();
      await letStorageFinish(t);

      expect(container.read(playerSettingsProvider).profiles, isEmpty);
      expect(api.cacheUsage.entries, 3);
      expect(await t.runAsync(() => store.countStartedSince(null)), 2);
    });

    testWidgets('Clear all data asks twice before it does anything', (
      t,
    ) async {
      await pump(t, games: 2);
      await openSheet(t);

      await t.tap(find.text('Clear all data'));
      await t.pumpAndSettle();
      expect(find.text('Clear all data?'), findsOneWidget);
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('This cannot be undone'), findsOneWidget);
      // Backing out at the second question leaves everything.
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();

      expect(await t.runAsync(() => store.countStartedSince(null)), 2);
      expect(container.read(playerSettingsProvider).name, 'Aceu');
    });
  });

  group('Clear cached responses', () {
    Future<void> openSheet(WidgetTester t) async {
      await t.tap(find.text('Clear data'));
      await t.pumpAndSettle();
    }

    testWidgets('shows how much is saved', (t) async {
      await pump(t, cached: 3);
      await openSheet(t);

      expect(
        find.textContaining(
          RegExp(r'^3 saved responses, \d+(\.\d)? (B|KB|MB)$'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('says when nothing is saved', (t) async {
      await pump(t);
      await openSheet(t);

      expect(find.text('Nothing saved'), findsOneWidget);
    });

    testWidgets('asks first, and Cancel keeps everything', (t) async {
      await pump(t, cached: 3);
      await openSheet(t);

      await t.tap(find.text('Clear cached responses'));
      await t.pumpAndSettle();
      expect(find.text('Clear cached responses?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();

      expect(api.cacheUsage.entries, 3);
    });

    testWidgets('clears the responses and nothing else', (t) async {
      await pump(t, games: 2, cached: 3);
      await openSheet(t);
      final bytesBefore = api.cacheUsage.bytes;

      await t.tap(find.text('Clear cached responses'));
      await t.pumpAndSettle();
      await t.tap(find.text('Clear'));
      await t.pump();
      await letStorageFinish(t);

      expect(api.cacheUsage.entries, 0);
      expect(
        find.text('Cleared 3 saved responses (${formatBytes(bytesBefore)}).'),
        findsOneWidget,
      );
      // The match history and the profile stay.
      expect(await t.runAsync(() => store.countStartedSince(null)), 2);
      expect(container.read(playerSettingsProvider).name, 'Aceu');
    });

    testWidgets('says so when there was nothing to clear', (t) async {
      await pump(t);
      await openSheet(t);

      await t.tap(find.text('Clear cached responses'));
      await t.pumpAndSettle();
      await t.tap(find.text('Clear'));
      await t.pump();
      await letStorageFinish(t);

      expect(find.text('Nothing was saved.'), findsOneWidget);
    });
  });
}
