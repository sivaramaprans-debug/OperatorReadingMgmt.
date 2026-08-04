import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../services/audit_service.dart';

class EditOperatorUseCase {
  const EditOperatorUseCase({
    required this.operatorsRepo,
    required this.devicesRepo,
    required this.auditService,
  });

  final SupabaseOperatorsRepository operatorsRepo;
  final SupabaseDevicesRepository devicesRepo;
  final AuditService auditService;

  Future<(bool, Failure?)> call({
    required String adminId,
    required String operatorId,
    required String fullName,
    required String username,
    required String phoneNumber,
    required List<String> assignedDeviceIds,
  }) async {
    // 1. Validate inputs
    final nameErr = Validators.fullName(fullName);
    if (nameErr != null) return (false, ValidationFailure(nameErr));

    final userErr = Validators.username(username);
    if (userErr != null) return (false, ValidationFailure(userErr));

    final phoneErr = Validators.phoneNumber(phoneNumber);
    if (phoneErr != null) return (false, ValidationFailure(phoneErr));

    try {
      // 2. Check existence
      final existing = await operatorsRepo.findById(operatorId);
      if (existing == null) {
        return (false, const NotFoundFailure('Operator not found.'));
      }

      // 3. Check unique username (if changed)
      if (existing.username != username.trim()) {
        final conflict = await operatorsRepo.findByUsername(username.trim());
        if (conflict != null) {
          return (false, const ValidationFailure('Username is already taken.'));
        }
      }

      // 4. Update and Audit
      await operatorsRepo.update(
        operatorId,
        fullName: fullName.trim(),
        username: username.trim(),
      );

      // Update assigned devices
      final currentDevices = await devicesRepo.getAssignedToOperator(operatorId);
      final currentDeviceIds = currentDevices.map((e) => e.id).toSet();
      final newDeviceIds = assignedDeviceIds.toSet();

      for (final deviceId in currentDeviceIds) {
        if (!newDeviceIds.contains(deviceId)) {
          await devicesRepo.unassignOperator(deviceId, operatorId);
        }
      }
      for (final deviceId in newDeviceIds) {
        if (!currentDeviceIds.contains(deviceId)) {
          await devicesRepo.assignOperator(deviceId, operatorId);
        }
      }

      await auditService.adminLog(
        adminId: adminId,
        action: 'operator.edit',
        entityType: 'operator',
        entityId: operatorId,
        metadata: {
          'before': {
            'fullName': existing.fullName,
            'username': existing.username,
          },
          'after': {
            'fullName': fullName.trim(),
            'username': username.trim(),
          }
        },
      );

      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Failed to edit operator: $e'));
    }
  }
}
