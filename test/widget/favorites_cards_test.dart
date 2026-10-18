import 'package:dio/dio.dart' show RequestOptions;
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/player_provider.dart';
import 'package:apexlytics/providers/search_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/search/favorites_pane.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/storage/api_cache_store.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/status_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

Map<String, Object?> _player(
  String name,
  String uid,
  String rank,
  int rp, {
  bool online = false,
}) => {
  'global': {
    'name': name,
    'uid': uid,
    'platform': 'PC',
    'level': 10,
    'rank': {'rankName': rank, 'rankScore': rp, 'rankDiv': 2},
  },
  'realtime': {'isOnline': online ? 1 : 0, 'isInGame': 0},
};

void main() {
  setUpAll(useFfiDatabase);

  var dbCounter = 0;

  // "1" and "2" are looked up this session (2 is offline); "3" fails; "4" is
  // never looked up and has nothing cached.
  const saved =
      '[{"query":"Alpha","platform":"PC","uid":"1"},'
      '{"query":"Bravo","platform":"PS4","uid":"2"},'
      '{"query":"Charlie","platform":"X1","uid":"3"},'
      '{"query":"Delta","platform":"PC","uid":"4"}]';

  Future<ProviderContainer> pumpPane(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({'search_favorites': saved});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        apiServiceProvider.overrideWithValue(
          ApiService(
            ApiCacheStore(
              overridePath:
                  'file:favorites_cards_${dbCounter++}?mode=memory&cache=shared',
            ),
            httpClientAdapter: FakeHttpAdapter({
              '/player/uid': (RequestOptions o) =>
                  switch (o.queryParameters['uid']) {
                    '1' => _player('Alpha', '1', 'Master', 52671, online: true),
                    '2' => _player('Bravo', '2', 'Platinum', 10330),
                    _ => const FakeReply(404, {'error': 'nobody'}),
                  },
            }),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    for (final uid in ['1', '2', '3']) {
      container.read(sessionRefreshedProvider.notifier).add(uid);
    }
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: FavoritesPane(onPick: (_) {})),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    return container;
  }

  /// The colour of the presence dot on the card of the favorite named [name].
  Color dotOf(WidgetTester t, String name) {
    final card = find.ancestor(
      of: find.text(name),
      matching: find.byType(InkWell),
    );
    return t
        .widget<StatusDot>(
          find.descendant(of: card.first, matching: find.byType(StatusDot)),
        )
        .color;
  }

  testWidgets('a looked-up favorite shows its rank and RP', (t) async {
    await pumpPane(t);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('PC · Master'), findsOneWidget);
    expect(find.text('52,671'), findsOneWidget);
    expect(find.text('PlayStation · Platinum II'), findsOneWidget);
    expect(find.text('10,330'), findsOneWidget);
    // One "RP" under each figure.
    expect(find.text('RP'), findsNWidgets(2));
  });

  testWidgets('one that has not been looked up shows only its platform', (
    t,
  ) async {
    await pumpPane(t);

    expect(find.text('Delta'), findsOneWidget);
    expect(find.text('PC'), findsOneWidget);
    // A person icon holds the place of a rank badge it doesn't have.
    final card = find.ancestor(
      of: find.text('Delta'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(
        of: card.first,
        matching: find.byIcon(Icons.person_outline),
      ),
      findsOneWidget,
    );
  });

  testWidgets('one that failed to load says so', (t) async {
    await pumpPane(t);

    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('Failed to load'), findsOneWidget);
  });

  testWidgets('the dot on each card says who is around', (t) async {
    await pumpPane(t);

    expect(dotOf(t, 'Alpha'), AppTheme.orange); // online, not in a game
    expect(dotOf(t, 'Bravo'), AppTheme.red); // offline
    expect(dotOf(t, 'Charlie'), AppTheme.red); // failed
    expect(dotOf(t, 'Delta'), AppTheme.muted); // not looked up
  });

  testWidgets('the favorites are cards, one under another, in order', (
    t,
  ) async {
    await pumpPane(t);

    final tops = [
      for (final n in ['Alpha', 'Bravo', 'Charlie', 'Delta'])
        t.getTopLeft(find.text(n)).dy,
    ];
    expect(tops, [...tops]..sort());
    // A card is taller than a plain row of text, with a gap between them.
    expect(tops[1] - tops[0], greaterThan(56));
  });

  group('the section headers', () {
    testWidgets('are titled with a quiet Clear at the end', (t) async {
      await pumpPane(t);

      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      final clear = t.widget<Text>(find.text('Clear'));
      expect(clear.style?.color, AppTheme.muted);
      expect(
        t.getTopLeft(find.text('Clear')).dx,
        greaterThan(t.getTopLeft(find.text('Favorites')).dx + 100),
      );
    });

    testWidgets('Clear on the favorites asks first, then clears them', (
      t,
    ) async {
      final container = await pumpPane(t);

      await t.tap(find.text('Clear'));
      await t.pumpAndSettle();
      expect(find.text('Clear favorites?'), findsOneWidget);
      expect(container.read(searchStateProvider).favorites, hasLength(4));

      await t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Clear'),
        ),
      );
      await t.pumpAndSettle();

      expect(container.read(searchStateProvider).favorites, isEmpty);
    });
  });
}
