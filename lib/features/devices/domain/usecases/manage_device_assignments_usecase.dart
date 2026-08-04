import '../../../../core/errors/failures.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../services/audit_service.dart';

class ManageDeviceAssignmentsUseCase {
  const ManageDeviceAssignmentsUseCase({required this.devicesRepo, required this.auditService});
  final SupabaseDevicesRepository devicesRepo;
  final AuditService auditService;

  Future<(bool, Failure?)> assign({
    required String adminId,
    required String operatorId,
    required String deviceId,
  }) async {
    try {
      final operators = await devicesRepo.getAssignedOperatorIds(deviceId);
      if (operators.contains(operatorId)) return (true, null);

      await devicesRepo.assignOperator(deviceId, operatorId);
      await auditService.adminLog(
        adminId: adminId,
        action: 'device.assign',
        entityType: 'operator_device',
        entityId: operatorId,
        metadata: {'device_id': deviceId},
      );
      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Failed to assign device: $e'));
    }
  }

  Future<(bool, Failure?)> unassign({
    required String adminId,
    required String operatorId,
    required String deviceId,
  }) async {
    try {
      await devicesRepo.unassignOperator(deviceId, operatorId);
      await auditService.adminLog(
        adminId: adminId,
        action: 'device.unassign',
        entityType: 'operator_device',
        entityId: operatorId,
        metadata: {'device_id': deviceId},
      );
      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Failed to unassign device: $e'));
    }
  }
}
