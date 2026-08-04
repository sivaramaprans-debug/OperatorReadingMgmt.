import 'dart:math';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../services/password_hashing_service.dart';
import '../../../../services/secure_storage_service.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Supabase-backed implementation of [AuthRepository].
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required SupabaseOperatorsRepository operatorsRepo,
    required SecureStorageService secureStorage,
  })  : _operatorsRepo = operatorsRepo,
        _secureStorage = secureStorage;

  final SupabaseOperatorsRepository _operatorsRepo;
  final SecureStorageService _secureStorage;
  final _uuid = const Uuid();

  // ── login ──────────────────────────────────────────────────────────────────

  @override
  Future<(AppUser?, Failure?)> login(String username, String password) async {
    try {
      final user = await _operatorsRepo.findByUsername(username);
      if (user == null) {
        return (null, AuthFailure.invalidCredentials);
      }

      if (!user.isActive) {
        return (null, AuthFailure.invalidCredentials);
      }

      final valid = PasswordHashingService.verify(password, user.passwordHash);
      if (!valid) {
        return (null, AuthFailure.invalidCredentials);
      }

      await _secureStorage.saveSession(userId: user.id, role: user.role);

      if (user.role == 'admin') {
        return (AdminUser(id: user.id, username: user.username), null);
      }

      return (
        OperatorUser(
          id: user.id,
          username: user.username,
          fullName: user.fullName,
        ),
        null,
      );
    } catch (e) {
      return (null, DatabaseFailure('Login failed: $e'));
    }
  }

  // ── restoreSession ─────────────────────────────────────────────────────────

  @override
  Future<AppUser?> restoreSession() async {
    try {
      final userId = await _secureStorage.getActiveUserId();
      final role = await _secureStorage.getActiveUserRole();
      if (userId == null || role == null) return null;

      final user = await _operatorsRepo.findById(userId);
      if (user == null || !user.isActive) {
        await _secureStorage.clearSession();
        return null;
      }

      if (role == 'admin') {
        return AdminUser(id: user.id, username: user.username);
      }
      return OperatorUser(
          id: user.id, username: user.username, fullName: user.fullName);
    } catch (_) {
      return null;
    }
  }

  // ── logout ─────────────────────────────────────────────────────────────────

  @override
  Future<void> logout() => _secureStorage.clearSession();

  // ── changePassword ─────────────────────────────────────────────────────────

  @override
  Future<(bool, Failure?)> changePassword({
    required String userId,
    required String role,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = await _operatorsRepo.findById(userId);
      if (user == null) {
        return (false, const NotFoundFailure('User not found.'));
      }
      if (!PasswordHashingService.verify(currentPassword, user.passwordHash)) {
        return (false, const AuthFailure('Current password is incorrect.'));
      }
      final newHash = PasswordHashingService.hash(newPassword);
      await _operatorsRepo.updatePasswordHash(userId, newHash);
      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Password change failed: $e'));
    }
  }

  // ── seedDefaultAdmin ───────────────────────────────────────────────────────

  @override
  Future<void> seedDefaultAdmin() async {
    final hash = PasswordHashingService.hash(AppConstants.defaultAdminPassword);
    await _operatorsRepo.seedDefaultAdmin(
        AppConstants.defaultAdminUsername, hash);
  }

  // ── Recovery code (stub — not needed for Supabase version) ────────────────

  @override
  Future<String> generateAdminRecoveryCode(String adminId) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final code = List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
    final plainCode = '${code.substring(0, 4)}-${code.substring(4, 8)}';
    final hash = PasswordHashingService.hashRecoveryCode(plainCode);
    await _secureStorage.saveAdminRecoveryHash(hash);
    return plainCode;
  }

  @override
  Future<(bool, Failure?)> resetAdminPasswordWithRecoveryCode({
    required String recoveryCode,
    required String newPassword,
  }) async {
    try {
      final storedHash = await _secureStorage.getAdminRecoveryHash();
      if (storedHash == null) {
        return (false, const AuthFailure('No recovery code set up.'));
      }
      if (!PasswordHashingService.verifyRecoveryCode(recoveryCode, storedHash)) {
        return (false, const AuthFailure('Invalid recovery code.'));
      }
      // Find admin user and update password
      final admin = await _operatorsRepo.findByUsername(
          AppConstants.defaultAdminUsername);
      if (admin == null) {
        return (false, const NotFoundFailure('Admin not found.'));
      }
      final newHash = PasswordHashingService.hash(newPassword);
      await _operatorsRepo.updatePasswordHash(admin.id, newHash);
      await _secureStorage.clearAdminRecoveryHash();
      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Password reset failed: $e'));
    }
  }
}
