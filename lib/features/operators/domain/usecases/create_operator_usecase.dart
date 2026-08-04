import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../services/audit_service.dart';
import '../../../../services/password_hashing_service.dart';

class CreateOperatorUseCase {
  const CreateOperatorUseCase({
    required this.operatorsRepo,
    required this.devicesRepo,
    required this.auditService,
  });

  final SupabaseOperatorsRepository operatorsRepo;
  final SupabaseDevicesRepository devicesRepo;
  final AuditService auditService;

  Future<(String?, Failure?)> call({
    required String adminId,
    required String fullName,
    required String username,
    required String password,
    required String phoneNumber,
    required List<String> assignedDeviceIds,
  }) async {
    // 1. Validate inputs
    final nameErr = Validators.fullName(fullName);
    if (nameErr != null) return (null, ValidationFailure(nameErr));

    final userErr = Validators.username(username);
    if (userErr != null) return (null, ValidationFailure(userErr));

    final passErr = Validators.password(password);
    if (passErr != null) return (null, ValidationFailure(passErr));

    final phoneErr = Validators.phoneNumber(phoneNumber);
    if (phoneErr != null) return (null, ValidationFailure(phoneErr));

    // 2. Check for unique username
    final existing = await operatorsRepo.findByUsername(username.trim());
    if (existing != null) {
      return (null, const ValidationFailure('Username is already taken.'));
    }

    try {
      final hash = PasswordHashingService.hash(password);

      // 3. Insert and Audit
      await operatorsRepo.create(
        username: username.trim(),
        fullName: fullName.trim(),
        passwordHash: hash,
        role: 'operator',
      );
      
      final createdUser = await operatorsRepo.findByUsername(username.trim());
      if (createdUser == null) {
         return (null, const DatabaseFailure('Failed to fetch created user.'));
      }
      final id = createdUser.id;

      for (final deviceId in assignedDeviceIds) {
        await devicesRepo.assignOperator(deviceId, id);
      }

      await auditService.adminLog(
        adminId: adminId,
        action: 'operator.create',
        entityType: 'operator',
        entityId: id,
        metadata: {'username': username.trim()},
      );

      return (id, null);
    } catch (e) {
      return (null, DatabaseFailure('Failed to create operator: $e'));
    }
  }
}
