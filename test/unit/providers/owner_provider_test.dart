import 'package:apexlytics/constants/api_constants.dart';
import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/owner_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/utils/error_messages.dart';
import 'package:apexlytics/utils/storage/owner_token_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockApiService extends Mock implements ApiService {}

class FakeOwnerTokenStore implements OwnerTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

void main() {
  late MockApiService api;
  late FakeOwnerTokenStore store;
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> setUpContainer([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiServiceProvider.overrideWithValue(api),
        ownerTokenStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
  }

  When<Future<({int status, dynamic data})>> stubVerify() => when(
    () => api.getWithStatus(
      ApiConstants.ownerVerifyPath,
      headers: any(named: 'headers'),
      failover: false,
    ),
  );

  setUp(() {
    api = MockApiService();
    store = FakeOwnerTokenStore();
  });

  group('OwnerNotifier', () {
    test('starts locked', () async {
      await setUpContainer();
      expect(container.read(ownerUnlockedProvider), isFalse);
    });

    test('an accepted token is stored and unlocks the device', () async {
      await setUpContainer();
      stubVerify().thenAnswer((_) async => (status: 204, data: null));

      final ok = await container
          .read(ownerUnlockedProvider.notifier)
          .unlock('  secret  ');

      expect(ok, isTrue);
      expect(container.read(ownerUnlockedProvider), isTrue);
      expect(store.token, 'secret');
      expect(prefs.getBool(PrefsKeys.ownerUnlocked), isTrue);
    });

    test('a rejected token changes nothing', () async {
      await setUpContainer();
      stubVerify().thenThrow(const AppException('nope', status: 401));

      final ok = await container
          .read(ownerUnlockedProvider.notifier)
          .unlock('wrong');

      expect(ok, isFalse);
      expect(container.read(ownerUnlockedProvider), isFalse);
      expect(store.token, isNull);
      expect(prefs.getBool(PrefsKeys.ownerUnlocked), isNull);
    });

    test(
      'a transport failure throws instead of reading as a wrong token',
      () async {
        await setUpContainer();
        stubVerify().thenThrow(const AppException('offline'));

        await expectLater(
          container.read(ownerUnlockedProvider.notifier).unlock('secret'),
          throwsA(isA<AppException>()),
        );
        expect(store.token, isNull);
        expect(container.read(ownerUnlockedProvider), isFalse);
      },
    );

    test('an empty token is refused without calling the server', () async {
      await setUpContainer();

      final ok = await container
          .read(ownerUnlockedProvider.notifier)
          .unlock('   ');

      expect(ok, isFalse);
      verifyNever(
        () => api.getWithStatus(
          any(),
          headers: any(named: 'headers'),
          failover: any(named: 'failover'),
        ),
      );
    });

    test('lock clears the token and the flag', () async {
      await setUpContainer({PrefsKeys.ownerUnlocked: true});
      store.token = 'secret';
      expect(container.read(ownerUnlockedProvider), isTrue);

      await container.read(ownerUnlockedProvider.notifier).lock();

      expect(container.read(ownerUnlockedProvider), isFalse);
      expect(store.token, isNull);
      expect(prefs.getBool(PrefsKeys.ownerUnlocked), isNull);
    });
  });
}
