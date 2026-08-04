import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../repositories/auth_repository.dart';

/// Use case: Admin local recovery-code password reset (§0.4a).
/// Generates a one-time recovery code (admin setup) or resets password using it.
class GenerateAdminRecoveryCodeUseCase {
  const GenerateAdminRecoveryCodeUseCase(this._repository);
  final AuthRepository _repository;

  /// Generates a new code; returns plaintext (show once to Admin).
  Future<String> call(String adminId) =>
      _repository.generateAdminRecoveryCode(adminId);
}

class ResetAdminPasswordWithRecoveryCodeUseCase {
  const ResetAdminPasswordWithRecoveryCodeUseCase(this._repository);
  final AuthRepository _repository;

  Future<(bool, Failure?)> call({
    required String recoveryCode,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (recoveryCode.trim().isEmpty) {
      return (
        false,
        const ValidationFailure('Recovery code is required.'),
      );
    }
    final newPasswordError = Validators.password(newPassword);
    if (newPasswordError != null) {
      return (false, ValidationFailure(newPasswordError));
    }
    final confirmError =
        Validators.confirmPassword(confirmPassword, newPassword);
    if (confirmError != null) {
      return (false, ValidationFailure(confirmError));
    }
    return _repository.resetAdminPasswordWithRecoveryCode(
      recoveryCode: recoveryCode.trim(),
      newPassword: newPassword,
    );
  }
}
