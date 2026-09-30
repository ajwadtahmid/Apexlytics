import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_logger.dart';

/// Keychain/Keystore-backed home for the owner token — the one secret the app
/// holds, so it stays out of SharedPreferences (and therefore out of backups).
class OwnerTokenStore {
  static const _key = 'owner_token';

  final FlutterSecureStorage _storage;
  OwnerTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  /// Null when unset — and also when the platform store is unreadable (a
  /// corrupted Android keystore, say). Owner mode is a convenience, so a read
  /// failure degrades to a regular user rather than breaking `/games`.
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (e) {
      log.w('owner token read failed', error: e);
      return null;
    }
  }

  Future<void> write(String token) => _storage.write(key: _key, value: token);

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (e) {
      log.w('owner token delete failed', error: e);
    }
  }
}
