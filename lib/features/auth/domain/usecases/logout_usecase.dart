import '../repositories/auth_repository.dart';

/// Use case: logs out the current user, clearing the secure session.
class LogoutUseCase {
  const LogoutUseCase(this._repository);
  final AuthRepository _repository;

  Future<void> call() => _repository.logout();
}
