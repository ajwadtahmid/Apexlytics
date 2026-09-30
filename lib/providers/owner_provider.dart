import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_constants.dart';
import '../constants/prefs_keys.dart';
import '../utils/error_messages.dart';
import '../utils/storage/owner_token_store.dart';
import 'api_provider.dart';
import 'settings_provider.dart';

final ownerTokenStoreProvider = Provider<OwnerTokenStore>(
  (ref) => OwnerTokenStore(),
);

/// Whether this device has been unlocked as the owner's. The flag only lifts
/// the client-side profile cap; the server decides `/games` privileges from
/// the token itself, so a stale flag can't grant anything there.
final ownerUnlockedProvider = NotifierProvider<OwnerNotifier, bool>(
  OwnerNotifier.new,
);

class OwnerNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(PrefsKeys.ownerUnlocked) ??
      false;

  /// Checks [token] with the server and, if accepted, stores it. Returns
  /// false for a rejected token; a transport failure throws, so the caller can
  /// tell "wrong token" from "couldn't reach the server".
  Future<bool> unlock(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return false;
    try {
      await ref
          .read(apiServiceProvider)
          .getWithStatus(
            ApiConstants.ownerVerifyPath,
            headers: {ApiConstants.ownerTokenHeader: trimmed},
            failover: false,
          );
    } on AppException catch (e) {
      if (e.status == 401) return false;
      rethrow;
    }
    await ref.read(ownerTokenStoreProvider).write(trimmed);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(PrefsKeys.ownerUnlocked, true);
    state = true;
    return true;
  }

  Future<void> lock() async {
    await ref.read(ownerTokenStoreProvider).clear();
    await ref.read(sharedPreferencesProvider).remove(PrefsKeys.ownerUnlocked);
    state = false;
  }
}
