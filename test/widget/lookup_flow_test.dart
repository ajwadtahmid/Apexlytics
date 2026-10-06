import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/search/search_screen.dart';
import 'package:apexlytics/screens/stats/stats_screen.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/formatting/search_utils.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:apexlytics/widgets/player_lookup_form.dart';
import 'package:apexlytics/widgets/profile_manager_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers.dart';

/// A player payload as the proxy returns it.
Map<String, Object?> player(String name, String uid, {String platform = 'PC'}) =>
    {
      'global': {
        'name': name,
        'uid': uid,
        'platform': platform,
        'level': 10,
        'rank': {'rankName': 'Gold', 'rankScore': 5000},
      },
    };

const _switchUidNotice =
    'Nintendo Switch players can only be found by UID, so UID search is on.';
const _switchWarning =
    'Nintendo Switch players can only be searched by UID. Pick another platform to search by name.';
const _cooldownNotice = 'One moment — try again in a few seconds.';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  var dbCounter = 0;

  /// Sqflite runs on a real isolate, which fake-async pumping can't wait for; give it real time.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> boot(
    WidgetTester tester,
    Widget home,
    FakeHttpAdapter adapter, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'uid_search_warning_shown': true,
      ...prefs,
    });
    final sp = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        apiServiceProvider.overrideWithValue(
          ApiService(
            ApiCacheStore(
              overridePath:
                  'file:lookup_flow_${dbCounter++}?mode=memory&cache=shared',
            ),
            httpClientAdapter: adapter,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: home),
      ),
    );
    await tester.pump();
    return container;
  }

  String fieldText(WidgetTester t) =>
      t.widget<TextField>(find.byType(TextField).first).controller!.text;

  bool uidSwitchOn(WidgetTester t) => t.widget<Switch>(find.byType(Switch)).value;

  Future<void> pickPlatform(WidgetTester t, String label) async {
    await t.tap(find.text(label));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  group('first-time setup', () {
    testWidgets('a found player is saved and the form goes away', (t) async {
      final c = await boot(
        t,
        const StatsScreen(),
        FakeHttpAdapter({'/player': player('Aceu', '1001')}),
      );
      await t.enterText(find.byType(TextField), 'Aceu');
      await t.tap(find.text('Find My Player'));
      await t.pump();
      await settle(t);

      expect(c.read(playerSettingsProvider).isPlayerSet, isTrue);
      expect(find.byType(PlayerLookupForm), findsNothing);
      // The replacement stats view starts requests and a timer; let them finish, then dispose it.
      await settle(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(minutes: 1));
    });

    testWidgets('a 200 with no player in it is an error, and saves nothing', (
      t,
    ) async {
      final c = await boot(
        t,
        const StatsScreen(),
        FakeHttpAdapter({'/player': <String, Object?>{}}),
      );
      await t.enterText(find.byType(TextField), 'Ghost');
      await t.tap(find.text('Find My Player'));
      await t.pump();
      await settle(t);

      expect(c.read(playerSettingsProvider).profiles, isEmpty);
      expect(
        find.text('Player not found. Check the name and platform.'),
        findsOneWidget,
      );
      expect(find.byType(PlayerLookupForm), findsOneWidget);
    });

    testWidgets('the same for a UID search, naming the UID', (t) async {
      await boot(
        t,
        const StatsScreen(),
        FakeHttpAdapter({'/player/uid': <String, Object?>{}}),
      );
      await t.tap(find.byType(Switch));
      await t.pump();
      await t.enterText(find.byType(TextField), '1234567890');
      await t.tap(find.text('Find My Player'));
      await t.pump();
      await settle(t);

      expect(
        find.text('Player not found. Check the UID and platform.'),
        findsOneWidget,
      );
    });
  });

  group('retrying', () {
    testWidgets('a retry right after a failed lookup goes through', (t) async {
      final adapter = FakeHttpAdapter(); // every route answers 404
      await boot(t, const StatsScreen(), adapter);
      await t.enterText(find.byType(TextField), 'Nobody');
      await t.tap(find.text('Find My Player'));
      await t.pump();
      await settle(t);
      expect(adapter.paths, ['/player']);

      await t.tap(find.text('Find My Player'));
      await t.pump();
      await settle(t);

      expect(adapter.paths, ['/player', '/player']);
    });

    testWidgets('a tap inside the cooldown says so instead of doing nothing', (
      t,
    ) async {
      final adapter = FakeHttpAdapter();
      final c = await boot(t, const StatsScreen(), adapter);
      // Someone (a favourites refresh, say) just fetched this player.
      c.read(refreshCooldownProvider).tryFire(playerRefreshKey('PC', 'aceu'));

      await t.enterText(find.byType(TextField), 'Aceu');
      await t.tap(find.text('Find My Player'));
      await t.pump();

      expect(find.text(_cooldownNotice), findsOneWidget);
      expect(adapter.requests, isEmpty);

      await t.enterText(find.byType(TextField), 'Aceu2');
      await t.pump();
      expect(find.text(_cooldownNotice), findsNothing);
    });
  });

  group('UID toggle', () {
    testWidgets('each mode keeps its own draft', (t) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());
      await t.enterText(find.byType(TextField), 'Aceu');

      await t.tap(find.byType(Switch));
      await t.pump();
      expect(fieldText(t), isEmpty);
      expect(find.text('UID must contain digits only.'), findsNothing);

      await t.enterText(find.byType(TextField), '12345');
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(fieldText(t), 'Aceu');

      await t.tap(find.byType(Switch));
      await t.pump();
      expect(fieldText(t), '12345');
    });

    testWidgets('a UID typed before ticking the box stays in the field', (
      t,
    ) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());
      await t.enterText(find.byType(TextField), '1012345678');

      await t.tap(find.byType(Switch));
      await t.pump();

      expect(uidSwitchOn(t), isTrue);
      expect(fieldText(t), '1012345678');
    });

    testWidgets('a name with letters does not keep its digits when switching '
        'to UID', (t) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());
      await t.enterText(find.byType(TextField), 'Aceu123');

      await t.tap(find.byType(Switch));
      await t.pump();

      expect(uidSwitchOn(t), isTrue);
      expect(fieldText(t), isEmpty);
    });

    testWidgets('a number carried across is gone once the name has letters', (
      t,
    ) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());
      await t.enterText(find.byType(TextField), '1012345678');
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(fieldText(t), '1012345678');

      await t.tap(find.byType(Switch));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Aceu1012345678');
      await t.tap(find.byType(Switch));
      await t.pump();

      expect(uidSwitchOn(t), isTrue);
      expect(fieldText(t), isEmpty);
    });

    testWidgets('the same in the search bar', (t) async {
      await boot(t, const SearchScreen(), FakeHttpAdapter());
      await t.enterText(find.byType(TextField), 'Aceu123');

      await t.tap(find.byType(Switch));
      await t.pump();

      expect(fieldText(t), isEmpty);
    });

    testWidgets('digits in the name field offer to search by UID', (t) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());
      const hint = 'Looks like a UID. Tap to search by UID.';

      await t.enterText(find.byType(TextField), 'Aceu');
      expect(find.text(hint), findsNothing);
      await t.enterText(find.byType(TextField), '12345');
      expect(find.text(hint), findsNothing, reason: 'too short for a UID');

      await t.enterText(find.byType(TextField), '1012345678');
      await t.pump();
      expect(find.text(hint), findsOneWidget);

      await t.tap(find.text(hint));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(uidSwitchOn(t), isTrue);
      expect(fieldText(t), '1012345678');
      expect(find.text(hint), findsNothing);
    });

    testWidgets('the same hint and carry-over work in the search bar', (
      t,
    ) async {
      await boot(t, const SearchScreen(), FakeHttpAdapter());
      await t.enterText(find.byType(TextField), '1012345678');
      await t.pump();

      await t.tap(find.text('Looks like a UID. Tap to search by UID.'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(uidSwitchOn(t), isTrue);
      expect(fieldText(t), '1012345678');
    });
  });

  group('Nintendo Switch is UID-only', () {
    testWidgets('picking it turns UID search on and says why', (t) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());
      await t.enterText(find.byType(TextField), 'Aceu');

      await pickPlatform(t, 'Nintendo Switch');

      expect(uidSwitchOn(t), isTrue);
      expect(fieldText(t), isEmpty, reason: 'the UID draft, not the name');
      expect(find.text(_switchUidNotice), findsOneWidget);
    });

    testWidgets('the toggle cannot be turned off while it is selected', (
      t,
    ) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());
      await pickPlatform(t, 'Nintendo Switch');

      await t.tap(find.byType(Switch));
      await t.pump();

      expect(uidSwitchOn(t), isTrue);
      expect(find.text(_switchWarning), findsOneWidget);
    });

    testWidgets('leaving Switch puts a toggle that was off back to off, with '
        'the name typed earlier', (t) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());
      await t.enterText(find.byType(TextField), 'Aceu');
      await pickPlatform(t, 'Nintendo Switch');
      expect(uidSwitchOn(t), isTrue);

      await pickPlatform(t, 'PC');

      expect(uidSwitchOn(t), isFalse);
      expect(fieldText(t), 'Aceu');
      expect(find.text(_switchUidNotice), findsNothing);
      // And it's free to use again.
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(uidSwitchOn(t), isTrue);
    });

    testWidgets('leaving Switch leaves a toggle that was already on, on', (
      t,
    ) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());
      await t.tap(find.byType(Switch)); // on, by choice
      await t.pump();
      await t.enterText(find.byType(TextField), '12345');

      await pickPlatform(t, 'Nintendo Switch');
      expect(uidSwitchOn(t), isTrue);
      expect(fieldText(t), '12345');

      for (final other in ['PlayStation', 'Xbox']) {
        await pickPlatform(t, other);
        expect(uidSwitchOn(t), isTrue, reason: other);
        expect(fieldText(t), '12345', reason: other);
        await pickPlatform(t, 'Nintendo Switch');
      }
    });

    testWidgets('each visit to Switch restores on its own way out', (t) async {
      await boot(t, const StatsScreen(), FakeHttpAdapter());

      await pickPlatform(t, 'Nintendo Switch');
      await pickPlatform(t, 'Xbox');
      expect(uidSwitchOn(t), isFalse);

      // Now turn it on by hand, then visit Switch: it must stay on after.
      await t.tap(find.byType(Switch));
      await t.pump();
      await pickPlatform(t, 'Nintendo Switch');
      await pickPlatform(t, 'PC');
      expect(uidSwitchOn(t), isTrue);
    });
  });

  group('profile sheet', () {
    const oneProfile = {
      'player_profiles': '[{"name":"Aceu","uid":"1001","platform":"PC"}]',
      'active_profile_index': 0,
    };

    Future<ProviderContainer> openSheet(
      WidgetTester t,
      FakeHttpAdapter adapter,
    ) async {
      final c = await boot(
        t,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ProfileManagerSheet(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        adapter,
        prefs: oneProfile,
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return c;
    }

    testWidgets('adding starts from a blank form, not the active profile', (
      t,
    ) async {
      await openSheet(t, FakeHttpAdapter());

      await t.tap(find.text('Add Profile'));
      await t.pump();

      expect(fieldText(t), isEmpty);
    });

    testWidgets('a successful add closes the sheet on the new profile', (
      t,
    ) async {
      final c = await openSheet(
        t,
        FakeHttpAdapter({'/player': player('Newbie', '2002')}),
      );
      await t.tap(find.text('Add Profile'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Newbie');
      await t.tap(find.widgetWithText(ElevatedButton, 'Add Profile'));
      await t.pump();
      await settle(t);
      await t.pumpAndSettle();

      final s = c.read(playerSettingsProvider);
      expect(s.profiles.map((p) => p.name), ['Aceu', 'Newbie']);
      expect(s.activeProfileIndex, 1);
      expect(find.byType(ProfileManagerSheet), findsNothing);
    });

    testWidgets('a failed add keeps the form open with the error', (t) async {
      final c = await openSheet(t, FakeHttpAdapter());
      await t.tap(find.text('Add Profile'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Nobody');
      await t.tap(find.widgetWithText(ElevatedButton, 'Add Profile'));
      await t.pump();
      await settle(t);

      expect(find.byType(ProfileManagerSheet), findsOneWidget);
      expect(find.byType(PlayerLookupForm), findsOneWidget);
      expect(c.read(playerSettingsProvider).profiles, hasLength(1));
    });

    testWidgets('editing pre-fills the name and a successful edit returns to '
        'the list', (t) async {
      final c = await openSheet(
        t,
        FakeHttpAdapter({'/player': player('Aceu2', '1001')}),
      );
      await t.tap(find.byIcon(Icons.edit_outlined));
      await t.pump();
      expect(fieldText(t), 'Aceu');

      await t.enterText(find.byType(TextField), 'Aceu2');
      await t.tap(find.widgetWithText(ElevatedButton, 'Update Profile'));
      await t.pump();
      await settle(t);

      expect(c.read(playerSettingsProvider).profiles.single.name, 'Aceu2');
      expect(find.byType(ProfileManagerSheet), findsOneWidget);
      expect(find.byType(PlayerLookupForm), findsNothing);
    });

    testWidgets('editing a Switch profile opens in UID mode on its UID', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await boot(
        t,
        const Scaffold(
          body: PlayerLookupForm(
            submitLabel: 'Update',
            initialName: 'SwitchGuy',
            initialPlatform: 'SWITCH',
            initialUid: '1099',
          ),
        ),
        FakeHttpAdapter(),
      );

      expect(uidSwitchOn(t), isTrue);
      expect(fieldText(t), '1099');

      // Switch forced UID search on, so moving off it returns to the name.
      await pickPlatform(t, 'PC');
      expect(uidSwitchOn(t), isFalse);
      expect(fieldText(t), 'SwitchGuy');
    });
  });

  group('Search tab', () {
    testWidgets('picking Switch turns UID search on, and the toggle then '
        'refuses to turn off', (t) async {
      await boot(t, const SearchScreen(), FakeHttpAdapter());

      await pickPlatform(t, 'Nintendo Switch');
      expect(uidSwitchOn(t), isTrue);
      expect(find.text(_switchUidNotice), findsOneWidget);

      await t.tap(find.byType(Switch));
      await t.pump();
      // The first snackbar has to finish hiding before the next one shows.
      await t.pump(const Duration(seconds: 1));
      expect(uidSwitchOn(t), isTrue);
      expect(find.text(_switchWarning), findsOneWidget);
    });

    testWidgets('leaving Switch restores the toggle to how it was', (t) async {
      await boot(t, const SearchScreen(), FakeHttpAdapter());
      await t.enterText(find.byType(TextField), 'Aceu');

      await pickPlatform(t, 'Nintendo Switch');
      expect(uidSwitchOn(t), isTrue);
      expect(fieldText(t), isEmpty);

      await pickPlatform(t, 'PC');
      expect(uidSwitchOn(t), isFalse);
      expect(fieldText(t), 'Aceu');
    });

    testWidgets('a toggle that was on stays on after Switch', (t) async {
      await boot(t, const SearchScreen(), FakeHttpAdapter());
      await t.tap(find.byType(Switch));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      await pickPlatform(t, 'Nintendo Switch');
      await pickPlatform(t, 'Xbox');

      expect(uidSwitchOn(t), isTrue);
    });

    testWidgets('picking a favourite while the bar is in UID mode puts the bar '
        'back in name mode', (t) async {
      await boot(
        t,
        const SearchScreen(),
        FakeHttpAdapter({'/player/uid': player('Aceu', '1001')}),
        prefs: {
          'search_favorites':
              '[{"query":"Aceu","platform":"PC","uid":"1001","byUid":false}]',
        },
      );
      await t.tap(find.byType(Switch));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(uidSwitchOn(t), isTrue);

      await t.tap(find.text('Aceu'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      final field = find.byType(TextField, skipOffstage: false).first;
      expect(
        (t.widget<TextField>(field).controller!.text),
        'Aceu',
      );
      expect(
        t.widget<Switch>(find.byType(Switch, skipOffstage: false)).value,
        isFalse,
      );
    });
  });
}
