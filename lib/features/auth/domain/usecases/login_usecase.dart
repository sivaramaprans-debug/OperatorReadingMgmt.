import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../entities/app_user.dart';
import '../repositories/auth_repository.dart';

/// Use case: Operator or Admin login.
/// Validates inputs in the domain layer before hitting the repository.
class LoginUseCase {
  const LoginUseCase(this._repository);
  final AuthRepository _repository;

  Future<(AppUser?, Failure?)> call({
    required String username,
    required String password,
  }) async {
    // Domain-layer validation (not just UI hints)
    final usernameError = Validators.username(username);
    if (usernameError != null) {
      return (null, ValidationFailure(usernameError));
    }
    if (password.isEmpty) {
      return (null, const ValidationFailure('Password is required.'));
    }
    return _repository.login(username.trim(), password);
  }
}
