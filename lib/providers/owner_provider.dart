import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_constants.dart';
import '../constants/prefs_keys.dart';
import '../utils/app_logger.dart';
import '../utils/error_messages.dart';
import '../utils/storage/owner_token_store.dart';
import 'api_provider.dart';
import 'settings_provider.dart';

/// The server accepted the owner token, but it couldn't be kept in the
/// platform's secure storage. Its own type so the UI can say so, instead of
/// reporting it as a wrong token or a network failure.
class OwnerTokenStorageException extends AppException {
  const OwnerTokenStorageException(super.message);
}

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
    try {
      await ref.read(ownerTokenStoreProvider).write(trimmed);
    } catch (e) {
      // The server accepted the token, but the platform's secure store
      // refused it (no Secret Service on Linux, a locked or corrupted
      // keystore). Say that, so it isn't mistaken for a wrong token or a
      // network problem — and don't flag the device as unlocked, since the
      // token that backs the flag was never kept. Type only: not the text.
      log.w('owner token write failed (${e.runtimeType})');
      throw const OwnerTokenStorageException(
        "The token was accepted, but this device couldn't store it securely. "
        'Owner mode is not enabled.',
      );
    }
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
