import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/backup_status_provider.dart';
import 'package:apexlytics/providers/navigation_provider.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/storage_usage_provider.dart';
import 'package:apexlytics/screens/settings/widgets/backup_reminder_banner.dart';
import 'package:apexlytics/screens/settings/widgets/cache_settings_section.dart';
import 'package:apexlytics/utils/storage/ranked_history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show inMemoryDatabasePath;

import '../helpers.dart';

void main() {
  setUpAll(useFfiDatabase);

  late RankedHistoryStore store;
  late ProviderContainer container;

  int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
  final now = DateTime.now();
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  /// Lets the count finish for real, then shows it.
  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => container.read(backupStatusProvider.future));
    await t.pump();
  }

  /// Settings' top and Data card, over a store holding games that started on
  /// [gameDays] days ago, with a backup [backupDays] ago when given.
  Future<void> pump(
    WidgetTester t, {
    required List<int> gameDays,
    int? backupDays,
  }) async {
    // In memory, and closing it would wait on the database under the fake clock.
    // The driver hands every test the same one, so empty it first.
    store = RankedHistoryStore(overridePath: inMemoryDatabasePath);
    await t.runAsync(store.deleteAll);
    await t.runAsync(
      () => store.upsertAll('1', [
        for (final d in gameDays) buildMatch(uid: '1', start: secs(daysAgo(d))),
      ]),
    );
    final (c, _) = await prefsContainer(
      values: {
        if (backupDays != null)
          PrefsKeys.lastBackupAt: daysAgo(backupDays).millisecondsSinceEpoch,
      },
      overrides: [
        rankedHistoryStoreProvider.overrideWithValue(store),
        apiServiceProvider.overrideWithValue(isolatedApiService()),
      ],
    );
    container = c;
    // The count reads a real database, which cannot finish under the test's
    // fake clock: keep the provider alive and let it finish for real first.
    await t.runAsync(() async {
      final keep = container.listen(backupStatusProvider, (_, _) {});
      addTearDown(keep.close);
      await container.read(backupStatusProvider.future);
      final keepUsage = container.listen(storageUsageProvider, (_, _) {});
      addTearDown(keepUsage.close);
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
            body: SingleChildScrollView(
              child: Column(
                children: [BackupReminderBanner(), CacheSettingsSection()],
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  Finder banner() => find.text('Back up your match history');

  group('the reminder at the top of Settings', () {
    testWidgets('appears after 15 days with games no backup holds', (t) async {
      await pump(t, gameDays: [3, 5, 20], backupDays: 16);

      expect(banner(), findsOneWidget);
      expect(
        find.text('2 games recorded since your last backup, 16 days ago.'),
        findsOneWidget,
      );
    });

    testWidgets('says so when there never was a backup', (t) async {
      await pump(t, gameDays: [1, 20, 30]);

      expect(banner(), findsOneWidget);
      expect(
        find.text('3 games recorded, and none backed up yet.'),
        findsOneWidget,
      );
    });

    testWidgets('stays away before the 15 days are up', (t) async {
      await pump(t, gameDays: [1, 2], backupDays: 14);

      expect(banner(), findsNothing);
    });

    testWidgets('stays away when nothing new was recorded', (t) async {
      // Every game is older than the backup.
      await pump(t, gameDays: [30, 40], backupDays: 20);

      expect(banner(), findsNothing);
    });

    testWidgets('stays away for a new install with no games', (t) async {
      await pump(t, gameDays: []);

      expect(banner(), findsNothing);
    });

    testWidgets('stays away for a history under 15 days old', (t) async {
      await pump(t, gameDays: [1, 9]);

      expect(banner(), findsNothing);
    });

    testWidgets('goes once a backup is made', (t) async {
      await pump(t, gameDays: [3, 20], backupDays: 16);
      expect(banner(), findsOneWidget);

      await t.runAsync(
        () => container.read(lastBackupProvider.notifier).markBackedUp(),
      );
      await settle(t);

      expect(banner(), findsNothing);
    });

    testWidgets('counts again when Settings is opened', (t) async {
      await pump(t, gameDays: [20], backupDays: 16);
      expect(banner(), findsNothing);

      // A game is recorded while Settings is out of view.
      await t.runAsync(
        () => store.upsertAll('1', [
          buildMatch(uid: '1', start: secs(daysAgo(2))),
        ]),
      );
      await t.runAsync(() async {
        container.read(currentTabProvider.notifier).setTab(AppTab.settings);
      });
      await settle(t);

      expect(banner(), findsOneWidget);
    });

    testWidgets('has an Export button', (t) async {
      await pump(t, gameDays: [3, 20], backupDays: 16);

      expect(
        find.descendant(
          of: find.byType(BackupReminderBanner),
          matching: find.text('Export'),
        ),
        findsOneWidget,
      );
    });
  });

  group('under Export data', () {
    testWidgets('says when the last backup was', (t) async {
      await pump(t, gameDays: [1], backupDays: 12);

      expect(find.textContaining('Backed up 12 days ago'), findsOneWidget);
    });

    testWidgets('says there has never been one', (t) async {
      await pump(t, gameDays: [1]);

      expect(find.textContaining('Never backed up'), findsOneWidget);
    });

    testWidgets('updates when a backup is made', (t) async {
      await pump(t, gameDays: [1], backupDays: 12);

      await t.runAsync(
        () => container.read(lastBackupProvider.notifier).markBackedUp(),
      );
      await t.pump();

      expect(find.textContaining('Backed up today'), findsOneWidget);
    });
  });

  test('a backup date is kept across launches', () async {
    final (c, prefs) = await prefsContainer();
    expect(c.read(lastBackupProvider), isNull);

    final at = DateTime(2026, 10, 1, 9, 30);
    await c.read(lastBackupProvider.notifier).markBackedUp(at);

    expect(c.read(lastBackupProvider), at);
    expect(prefs.getInt(PrefsKeys.lastBackupAt), at.millisecondsSinceEpoch);
    final (again, _) = await prefsContainer(
      values: {PrefsKeys.lastBackupAt: at.millisecondsSinceEpoch},
    );
    expect(again.read(lastBackupProvider), at);
  });
}
