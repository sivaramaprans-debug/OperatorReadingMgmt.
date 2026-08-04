import '../repositories/auth_repository.dart';

/// Use case: seeds the default Admin on first launch.
/// Called from main.dart before the router is initialized.
/// Is idempotent — safe to call every launch; does nothing if Admin exists.
class SeedAdminUseCase {
  const SeedAdminUseCase(this._repository);
  final AuthRepository _repository;

  Future<void> call() => _repository.seedDefaultAdmin();
}
