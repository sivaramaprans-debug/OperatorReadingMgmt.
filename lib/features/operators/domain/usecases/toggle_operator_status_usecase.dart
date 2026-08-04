import '../../../../core/errors/failures.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../services/audit_service.dart';

class ToggleOperatorStatusUseCase {
  const ToggleOperatorStatusUseCase({
    required this.operatorsRepo,
    required this.auditService,
  });

  final SupabaseOperatorsRepository operatorsRepo;
  final AuditService auditService;

  Future<(bool, Failure?)> call({
    required String adminId,
    required String operatorId,
    required bool isActive,
  }) async {
    try {
      final existing = await operatorsRepo.findById(operatorId);
      if (existing == null) {
        return (false, const NotFoundFailure('Operator not found.'));
      }

      if (existing.isActive == isActive) {
        return (true, null); // Nothing to change
      }

      await operatorsRepo.setActive(operatorId, active: isActive);

      await auditService.adminLog(
        adminId: adminId,
        action: isActive ? 'operator.activate' : 'operator.deactivate',
        entityType: 'operator',
        entityId: operatorId,
      );

      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Failed to change status: $e'));
    }
  }
}
