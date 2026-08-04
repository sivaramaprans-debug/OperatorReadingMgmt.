import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../main.dart';
import '../../../../services/audit_service.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../../dashboard/presentation/notifiers/admin_dashboard_notifier.dart';
import '../notifiers/operators_list_notifier.dart';
import '../../domain/usecases/create_operator_usecase.dart';
import '../../domain/usecases/edit_operator_usecase.dart';
import '../../domain/usecases/reset_operator_password_usecase.dart';

final createOperatorUseCaseProvider = Provider((ref) {
  final operatorsRepo = ref.watch(supabaseOperatorsRepoProvider);
  final devicesRepo = ref.watch(supabaseDevicesRepoProvider);
  final auditService = ref.watch(auditServiceProvider);
  return CreateOperatorUseCase(operatorsRepo: operatorsRepo, devicesRepo: devicesRepo, auditService: auditService);
});

final editOperatorUseCaseProvider = Provider((ref) {
  final operatorsRepo = ref.watch(supabaseOperatorsRepoProvider);
  final devicesRepo = ref.watch(supabaseDevicesRepoProvider);
  final auditService = ref.watch(auditServiceProvider);
  return EditOperatorUseCase(operatorsRepo: operatorsRepo, devicesRepo: devicesRepo, auditService: auditService);
});

final resetOperatorPasswordUseCaseProvider = Provider((ref) {
  final operatorsRepo = ref.watch(supabaseOperatorsRepoProvider);
  final auditService = ref.watch(auditServiceProvider);
  return ResetOperatorPasswordUseCase(operatorsRepo: operatorsRepo, auditService: auditService);
});

class OperatorFormState {
  const OperatorFormState({
    this.isLoading = false,
    this.error,
    this.success = false,
  });

  final bool isLoading;
  final String? error;
  final bool success;

  OperatorFormState copyWith({
    bool? isLoading,
    String? error,
    bool? success,
  }) {
    return OperatorFormState(
      isLoading: isLoading ?? this.isLoading,
      error: error, // overwrite error if explicitly passed, or null
      success: success ?? this.success,
    );
  }
}

class OperatorFormNotifier extends AutoDisposeNotifier<OperatorFormState> {
  @override
  OperatorFormState build() => const OperatorFormState();

  Future<void> createOperator({
    required String fullName,
    required String username,
    required String password,
    required String phoneNumber,
    required List<String> assignedDeviceIds,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    
    final admin = ref.read(authNotifierProvider.notifier).currentUser;
    if (admin == null || !admin.isAdmin) {
      state = state.copyWith(isLoading: false, error: 'Unauthorized');
      return;
    }

    final useCase = ref.read(createOperatorUseCaseProvider);
    final (_, failure) = await useCase(
      adminId: admin.id,
      fullName: fullName,
      username: username,
      password: password,
      phoneNumber: phoneNumber,
      assignedDeviceIds: assignedDeviceIds,
    );

    if (failure != null) {
      state = state.copyWith(isLoading: false, error: failure.message);
    } else {
      state = state.copyWith(isLoading: false, success: true);
      ref.invalidate(operatorsListProvider);
      ref.invalidate(adminDashboardStatsProvider);
    }
  }

  Future<void> editOperator({
    required String operatorId,
    required String fullName,
    required String username,
    required String phoneNumber,
    required List<String> assignedDeviceIds,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    
    final admin = ref.read(authNotifierProvider.notifier).currentUser;
    if (admin == null || !admin.isAdmin) {
      state = state.copyWith(isLoading: false, error: 'Unauthorized');
      return;
    }

    final useCase = ref.read(editOperatorUseCaseProvider);
    final (success, failure) = await useCase(
      adminId: admin.id,
      operatorId: operatorId,
      fullName: fullName,
      username: username,
      phoneNumber: phoneNumber,
      assignedDeviceIds: assignedDeviceIds,
    );

    if (failure != null || !success) {
      state = state.copyWith(isLoading: false, error: failure?.message ?? 'Edit failed');
    } else {
      state = state.copyWith(isLoading: false, success: true);
      ref.invalidate(operatorsListProvider);
      ref.invalidate(adminDashboardStatsProvider);
    }
  }

  Future<bool> resetPassword(String operatorId, String newPassword) async {
    state = state.copyWith(isLoading: true, error: null);
    
    final admin = ref.read(authNotifierProvider.notifier).currentUser;
    if (admin == null || !admin.isAdmin) {
      state = state.copyWith(isLoading: false, error: 'Unauthorized');
      return false;
    }

    final useCase = ref.read(resetOperatorPasswordUseCaseProvider);
    final (success, failure) = await useCase(
      adminId: admin.id,
      operatorId: operatorId,
      newPassword: newPassword,
    );

    if (failure != null || !success) {
      state = state.copyWith(isLoading: false, error: failure?.message ?? 'Reset failed');
      return false;
    } else {
      state = state.copyWith(isLoading: false, success: true);
      return true;
    }
  }
}

final operatorFormNotifierProvider =
    NotifierProvider.autoDispose<OperatorFormNotifier, OperatorFormState>(
        OperatorFormNotifier.new);
