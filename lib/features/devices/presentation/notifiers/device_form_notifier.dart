import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../../dashboard/presentation/notifiers/admin_dashboard_notifier.dart';
import '../notifiers/devices_list_notifier.dart';
import '../../domain/usecases/create_device_usecase.dart';
import '../../domain/usecases/edit_device_usecase.dart';

final createDeviceUseCaseProvider = Provider((ref) =>
    CreateDeviceUseCase(devicesRepo: ref.watch(supabaseDevicesRepoProvider)));
final editDeviceUseCaseProvider = Provider((ref) =>
    EditDeviceUseCase(devicesRepo: ref.watch(supabaseDevicesRepoProvider)));

class DeviceFormState {
  const DeviceFormState({this.isLoading = false, this.error, this.success = false});
  final bool isLoading;
  final String? error;
  final bool success;
  DeviceFormState copyWith({bool? isLoading, String? error, bool? success}) =>
      DeviceFormState(
          isLoading: isLoading ?? this.isLoading,
          error: error,
          success: success ?? this.success);
}

class DeviceFormNotifier extends AutoDisposeNotifier<DeviceFormState> {
  @override
  DeviceFormState build() => const DeviceFormState();

  Future<void> createDevice(
    String name,
    double factor, {
    required List<String> matrix,
    required List<String> dayMatrix,
    required bool requiresHeatDay,
    Map<String, double> heatUnitFactors = const {},
    Map<String, double> dayUnitFactors = const {},
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    final admin = ref.read(authNotifierProvider.notifier).currentUser;
    if (admin == null || !admin.isAdmin) {
      state = state.copyWith(isLoading: false, error: 'Unauthorized');
      return;
    }

    final useCase = ref.read(createDeviceUseCaseProvider);
    final (_, failure) = await useCase(
      adminId: admin.id,
      name: name,
      factor: factor,
      matrix: matrix,
      dayMatrix: dayMatrix,
      requiresHeatDay: requiresHeatDay,
      heatUnitFactors: heatUnitFactors,
      dayUnitFactors: dayUnitFactors,
    );

    if (failure != null) {
      state = state.copyWith(isLoading: false, error: failure.message);
    } else {
      state = state.copyWith(isLoading: false, success: true);
      ref.invalidate(devicesListProvider);
      ref.invalidate(adminDashboardStatsProvider);
    }
  }

  Future<void> editDevice(
    String deviceId,
    String name,
    double factor, {
    required List<String> matrix,
    required List<String> dayMatrix,
    required bool requiresHeatDay,
    Map<String, double> heatUnitFactors = const {},
    Map<String, double> dayUnitFactors = const {},
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    final admin = ref.read(authNotifierProvider.notifier).currentUser;
    if (admin == null || !admin.isAdmin) {
      state = state.copyWith(isLoading: false, error: 'Unauthorized');
      return;
    }

    final useCase = ref.read(editDeviceUseCaseProvider);
    final (success, failure) = await useCase(
      adminId: admin.id,
      deviceId: deviceId,
      name: name,
      factor: factor,
      matrix: matrix,
      dayMatrix: dayMatrix,
      requiresHeatDay: requiresHeatDay,
      heatUnitFactors: heatUnitFactors,
      dayUnitFactors: dayUnitFactors,
    );

    if (failure != null || !success) {
      state = state.copyWith(
          isLoading: false, error: failure?.message ?? 'Edit failed');
    } else {
      state = state.copyWith(isLoading: false, success: true);
      ref.invalidate(devicesListProvider);
      ref.invalidate(adminDashboardStatsProvider);
    }
  }
}

final deviceFormNotifierProvider =
    NotifierProvider.autoDispose<DeviceFormNotifier, DeviceFormState>(
        DeviceFormNotifier.new);
