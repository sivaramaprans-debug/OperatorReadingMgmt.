import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../domain/usecases/add_reading_usecase.dart';
import '../../domain/usecases/edit_reading_usecase.dart';
import '../../../dashboard/presentation/notifiers/operator_dashboard_notifier.dart';
import '../../../dashboard/presentation/notifiers/admin_dashboard_notifier.dart';

final addReadingUseCaseProvider = Provider((ref) => AddReadingUseCase(
      devicesRepo: ref.watch(supabaseDevicesRepoProvider),
      readingsRepo: ref.watch(supabaseReadingsRepoProvider),
    ));

final editReadingUseCaseProvider = Provider((ref) =>
    EditReadingUseCase(readingsRepo: ref.watch(supabaseReadingsRepoProvider)));

class ReadingFormState {
  const ReadingFormState({this.isLoading = false, this.error, this.success = false});
  final bool isLoading;
  final String? error;
  final bool success;
  ReadingFormState copyWith({bool? isLoading, String? error, bool? success}) =>
      ReadingFormState(
          isLoading: isLoading ?? this.isLoading,
          error: error,
          success: success ?? this.success);
}

class ReadingFormNotifier extends AutoDisposeNotifier<ReadingFormState> {
  @override
  ReadingFormState build() => const ReadingFormState();

  Future<void> submitReading({
    required String deviceId,
    required String readingType,
    required String heatNumber,
    required Map<String, double> values,
    int? readingDate,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    final user = ref.read(authNotifierProvider.notifier).currentUser;
    if (user == null) {
      state = state.copyWith(isLoading: false, error: 'Unauthorized');
      return;
    }

    final useCase = ref.read(addReadingUseCaseProvider);
    final (_, failure) = await useCase(
      operatorId: user.id,
      deviceId: deviceId,
      readingType: readingType,
      heatNumber: heatNumber,
      values: values,
      readingDate: readingDate,
    );

    if (failure != null) {
      state = state.copyWith(isLoading: false, error: failure.message);
    } else {
      state = state.copyWith(isLoading: false, success: true);
      ref.invalidate(operatorDashboardStatsProvider);
      ref.invalidate(adminDashboardStatsProvider);
    }
  }

  Future<void> editReading({
    required String readingId,
    required String readingType,
    required String heatNumber,
    required Map<String, double> values,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    final user = ref.read(authNotifierProvider.notifier).currentUser;
    if (user == null) {
      state = state.copyWith(isLoading: false, error: 'Unauthorized');
      return;
    }

    final useCase = ref.read(editReadingUseCaseProvider);
    final (success, failure) = await useCase(
      operatorId: user.id,
      readingId: readingId,
      readingType: readingType,
      heatNumber: heatNumber,
      values: values,
    );

    if (failure != null || !success) {
      state = state.copyWith(
          isLoading: false, error: failure?.message ?? 'Edit failed');
    } else {
      state = state.copyWith(isLoading: false, success: true);
      ref.invalidate(operatorDashboardStatsProvider);
      ref.invalidate(adminDashboardStatsProvider);
    }
  }
}

final readingFormNotifierProvider =
    NotifierProvider.autoDispose<ReadingFormNotifier, ReadingFormState>(
        ReadingFormNotifier.new);
