import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../main.dart';
import '../../../../services/audit_service.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../domain/usecases/manage_device_assignments_usecase.dart';

final manageDeviceAssignmentsUseCaseProvider = Provider((ref) => ManageDeviceAssignmentsUseCase(
    devicesRepo: ref.watch(supabaseDevicesRepoProvider), auditService: ref.watch(auditServiceProvider)));

final operatorAssignmentsProvider = FutureProvider.family<List<SupabaseDevice>, String>((ref, operatorId) {
  return ref.watch(supabaseDevicesRepoProvider).getAssignedToOperator(operatorId);
});

class DeviceAssignmentsNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> assign(String operatorId, String deviceId) async {
    state = const AsyncLoading();
    final admin = ref.read(authNotifierProvider.notifier).currentUser;
    if (admin == null) return false;

    final useCase = ref.read(manageDeviceAssignmentsUseCaseProvider);
    final (success, failure) = await useCase.assign(adminId: admin.id, operatorId: operatorId, deviceId: deviceId);

    if (!success) {
      state = AsyncError(failure?.message ?? 'Assign failed', StackTrace.current);
      return false;
    }
    ref.invalidate(operatorAssignmentsProvider(operatorId));
    state = const AsyncData(null);
    return true;
  }

  Future<bool> unassign(String operatorId, String deviceId) async {
    state = const AsyncLoading();
    final admin = ref.read(authNotifierProvider.notifier).currentUser;
    if (admin == null) return false;

    final useCase = ref.read(manageDeviceAssignmentsUseCaseProvider);
    final (success, failure) = await useCase.unassign(adminId: admin.id, operatorId: operatorId, deviceId: deviceId);

    if (!success) {
      state = AsyncError(failure?.message ?? 'Unassign failed', StackTrace.current);
      return false;
    }
    ref.invalidate(operatorAssignmentsProvider(operatorId));
    state = const AsyncData(null);
    return true;
  }
}

final deviceAssignmentsNotifierProvider =
    NotifierProvider<DeviceAssignmentsNotifier, AsyncValue<void>>(DeviceAssignmentsNotifier.new);
