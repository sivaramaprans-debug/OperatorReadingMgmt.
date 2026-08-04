import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../repositories/auth_repository.dart';

/// Use case: changes password for any user (Operator or Admin).
/// Validates the new password at the domain layer before calling the repo.
class ChangePasswordUseCase {
  const ChangePasswordUseCase(this._repository);
  final AuthRepository _repository;

  Future<(bool, Failure?)> call({
    required String userId,
    required String role,
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    // Domain validation
    if (currentPassword.isEmpty) {
      return (false, const ValidationFailure('Current password is required.'));
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
    if (newPassword == currentPassword) {
      return (
        false,
        const ValidationFailure(
          'New password must be different from current password.',
        ),
      );
    }
    return _repository.changePassword(
      userId: userId,
      role: role,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }
}
