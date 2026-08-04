import '../../../../core/errors/failures.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../services/audit_service.dart';

class ToggleDeviceStatusUseCase {
  const ToggleDeviceStatusUseCase({required this.devicesRepo, required this.auditService});
  final SupabaseDevicesRepository devicesRepo;
  final AuditService auditService;

  Future<(bool, Failure?)> call({
    required String adminId,
    required String deviceId,
    required bool isActive,
  }) async {
    try {
      final existing = await devicesRepo.findById(deviceId);
      if (existing == null) return (false, const NotFoundFailure('Device not found.'));
      
      if (existing.isActive == isActive) return (true, null);

      await devicesRepo.setActive(deviceId, active: isActive);
      await auditService.adminLog(
        adminId: adminId,
        action: isActive ? 'device.activate' : 'device.deactivate',
        entityType: 'device',
        entityId: deviceId,
      );
      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Failed to change status: $e'));
    }
  }
}
