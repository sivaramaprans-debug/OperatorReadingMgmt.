import '../../../../core/errors/failures.dart';
import '../entities/app_user.dart';

/// Repository interface for authentication operations.
/// Implemented in the data layer; domain only depends on this interface.
abstract interface class AuthRepository {
  /// Attempts to log in with [username] and [password].
  /// Returns [AppUser] on success, [AuthFailure] on bad credentials.
  Future<(AppUser?, Failure?)> login(String username, String password);

  /// Restores an active session from secure storage.
  /// Returns the [AppUser] if the session is valid, or null if none.
  Future<AppUser?> restoreSession();

  /// Clears the current session from secure storage.
  Future<void> logout();

  /// Changes the password for [userId] (any role).
  /// Verifies [currentPassword] before applying [newPassword].
  Future<(bool, Failure?)> changePassword({
    required String userId,
    required String role,
    required String currentPassword,
    required String newPassword,
  });

  /// Seeds the default Admin (admin / admin123) if none exists.
  /// Safe to call multiple times — is a no-op if an Admin already exists.
  Future<void> seedDefaultAdmin();

  /// Generates and stores a new local recovery code for the Admin.
  /// Returns the plaintext code (shown once to the Admin, never again).
  Future<String> generateAdminRecoveryCode(String adminId);

  /// Resets the Admin's password using the [recoveryCode].
  /// Returns failure if the code is wrong or no code is set.
  Future<(bool, Failure?)> resetAdminPasswordWithRecoveryCode({
    required String recoveryCode,
    required String newPassword,
  });
}
