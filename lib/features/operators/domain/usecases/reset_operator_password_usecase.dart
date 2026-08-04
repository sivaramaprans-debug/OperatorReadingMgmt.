import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../services/audit_service.dart';
import '../../../../services/password_hashing_service.dart';

class ResetOperatorPasswordUseCase {
  const ResetOperatorPasswordUseCase({
    required this.operatorsRepo,
    required this.auditService,
  });

  final SupabaseOperatorsRepository operatorsRepo;
  final AuditService auditService;

  Future<(bool, Failure?)> call({
    required String adminId,
    required String operatorId,
    required String newPassword,
  }) async {
    final passErr = Validators.password(newPassword);
    if (passErr != null) return (false, ValidationFailure(passErr));

    try {
      final existing = await operatorsRepo.findById(operatorId);
      if (existing == null) {
        return (false, const NotFoundFailure('Operator not found.'));
      }

      final hash = PasswordHashingService.hash(newPassword);

      await operatorsRepo.updatePasswordHash(operatorId, hash);

      await auditService.adminLog(
        adminId: adminId,
        action: 'operator.admin_password_reset',
        entityType: 'operator',
        entityId: operatorId,
      );

      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Failed to reset password: $e'));
    }
  }
}
