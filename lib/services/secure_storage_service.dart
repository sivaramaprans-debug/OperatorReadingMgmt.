import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants/app_constants.dart';

/// Wraps flutter_secure_storage (Keystore-backed on Android).
/// All session tokens and role markers live here — never in SharedPreferences.
/// Non-sensitive settings (theme, filters) belong in SharedPreferences.
class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final FlutterSecureStorage _storage;

  // ── Session ────────────────────────────────────────────────────────────────

  Future<void> saveSession({
    required String userId,
    required String role, // 'admin' | 'operator'
  }) async {
    await _storage.write(
        key: AppConstants.secureKeyActiveUserId, value: userId);
    await _storage.write(
        key: AppConstants.secureKeyActiveUserRole, value: role);
    await _storage.write(
        key: AppConstants.secureKeySessionToken,
        value: DateTime.now().millisecondsSinceEpoch.toString());
  }

  Future<String?> getActiveUserId() =>
      _storage.read(key: AppConstants.secureKeyActiveUserId);

  Future<String?> getActiveUserRole() =>
      _storage.read(key: AppConstants.secureKeyActiveUserRole);

  Future<String?> getSessionToken() =>
      _storage.read(key: AppConstants.secureKeySessionToken);

  Future<void> clearSession() async {
    await _storage.delete(key: AppConstants.secureKeyActiveUserId);
    await _storage.delete(key: AppConstants.secureKeyActiveUserRole);
    await _storage.delete(key: AppConstants.secureKeySessionToken);
  }

  // ── Recovery code ──────────────────────────────────────────────────────────

  Future<void> saveAdminRecoveryHash(String hash) =>
      _storage.write(key: AppConstants.secureKeyAdminRecoveryCode, value: hash);

  Future<String?> getAdminRecoveryHash() =>
      _storage.read(key: AppConstants.secureKeyAdminRecoveryCode);

  Future<void> clearAdminRecoveryHash() =>
      _storage.delete(key: AppConstants.secureKeyAdminRecoveryCode);

  // ── Generic ────────────────────────────────────────────────────────────────

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();
}
