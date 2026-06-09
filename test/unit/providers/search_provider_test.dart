import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/providers/search_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('SearchNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
    });

    test('initializes with empty favorites', () async {
      final state = container.read(searchStateProvider);
      expect(state.favorites, isEmpty);
    });

    test('adds a new favorite', () async {
      const playerRef = PlayerRef(
        query: 'TestPlayer',
        platform: 'PC',
        uid: '123',
      );

      await container.read(searchStateProvider.notifier).toggleFavorite(playerRef);

      final state = container.read(searchStateProvider);
      expect(state.favorites, contains(playerRef));
    });

    test('removes a favorite when toggled again', () async {
      const playerRef = PlayerRef(
        query: 'TestPlayer',
        platform: 'PC',
        uid: '123',
      );

      final notifier = container.read(searchStateProvider.notifier);
      await notifier.toggleFavorite(playerRef);
      await notifier.toggleFavorite(playerRef);

      final state = container.read(searchStateProvider);
      expect(state.favorites, isEmpty);
    });

    test('deduplicates by UID when both entries have UIDs', () async {
      const player1 = PlayerRef(
        query: 'OldName',
        platform: 'PC',
        uid: '123',
      );
      const player2 = PlayerRef(
        query: 'TestPlayer2',
        platform: 'PC',
        uid: '456',
      );

      final notifier = container.read(searchStateProvider.notifier);
      await notifier.toggleFavorite(player1);
      await notifier.toggleFavorite(player2);

      final state = container.read(searchStateProvider);
      expect(state.favorites, hasLength(2));
      // player2 is inserted at position 0, so it should be first
      expect(state.favorites.first.uid, '456');
      expect(state.favorites.last.uid, '123');
    });

    test('syncs display name for existing favorites', () async {
      const playerRef = PlayerRef(
        query: 'OldName',
        platform: 'PC',
        uid: null,
      );

      final notifier = container.read(searchStateProvider.notifier);
      await notifier.toggleFavorite(playerRef);

      // syncDisplayName matches by name, enriches with UID
      await notifier.syncDisplayName('123', 'OldName');

      final state = container.read(searchStateProvider);
      expect(state.favorites, hasLength(1));
      expect(state.favorites.first.uid, '123');
      expect(state.favorites.first.query, 'OldName');
    });

    test('clears all favorites', () async {
      const playerRef = PlayerRef(
        query: 'TestPlayer',
        platform: 'PC',
        uid: '123',
      );

      final notifier = container.read(searchStateProvider.notifier);
      await notifier.toggleFavorite(playerRef);
      await notifier.clearFavorites();

      final state = container.read(searchStateProvider);
      expect(state.favorites, isEmpty);
    });
  });
}
