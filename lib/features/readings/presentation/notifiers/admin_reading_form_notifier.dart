import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../dashboard/presentation/notifiers/admin_dashboard_notifier.dart';

class AdminReadingFormState {
  const AdminReadingFormState({this.isLoading = false, this.error, this.success = false});
  final bool isLoading;
  final String? error;
  final bool success;
  AdminReadingFormState copyWith({bool? isLoading, String? error, bool? success}) =>
      AdminReadingFormState(
          isLoading: isLoading ?? this.isLoading,
          error: error,
          success: success ?? this.success);
}

class AdminReadingFormNotifier extends AutoDisposeNotifier<AdminReadingFormState> {
  @override
  AdminReadingFormState build() => const AdminReadingFormState();

  Future<void> submitReading({
    required String operatorId,
    required String deviceId,
    required int readingDate,
    required String readingType,
    required String heatNumber,
    required Map<String, double> values,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(supabaseReadingsRepoProvider);
      
      final finalHeatNumber =
          (readingType == 'day' || readingType == 'standard') ? '' : heatNumber.trim();
          
      // Check for duplicates
      final isDuplicate = await repo.existsDuplicate(
        deviceId: deviceId,
        readingDateMs: readingDate,
        readingType: readingType,
        heatNumber: finalHeatNumber,
      );

      if (isDuplicate) {
        state = state.copyWith(isLoading: false, error: 'A reading of this type already exists for the selected date/heat.');
        return;
      }

      await repo.insert(
        operatorId: operatorId,
        deviceId: deviceId,
        readingDate: readingDate,
        readingType: readingType,
        heatNumber: finalHeatNumber,
        readingValues: jsonEncode(values),
      );

      state = state.copyWith(isLoading: false, success: true);
      ref.invalidate(adminDashboardStatsProvider);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to save reading: $e');
    }
  }

  Future<void> editReading({
    required String readingId,
    required int readingDate,
    required String readingType,
    required String heatNumber,
    required Map<String, double> values,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(supabaseReadingsRepoProvider);
      
      final finalHeatNumber =
          (readingType == 'day' || readingType == 'standard') ? '' : heatNumber.trim();
          
      final existing = await repo.findById(readingId);
      if (existing == null) {
        state = state.copyWith(isLoading: false, error: 'Reading not found');
        return;
      }

      if (existing.readingDate != readingDate || existing.readingType != readingType || existing.heatNumber != finalHeatNumber) {
        final isDuplicate = await repo.existsDuplicate(
          deviceId: existing.deviceId,
          readingDateMs: readingDate,
          readingType: readingType,
          heatNumber: finalHeatNumber,
          excludeId: readingId,
        );
        if (isDuplicate) {
          state = state.copyWith(isLoading: false, error: 'A reading of this type already exists for the selected date/heat.');
          return;
        }
      }

      await repo.update(
        readingId,
        readingDate: readingDate,
        readingType: readingType,
        heatNumber: finalHeatNumber,
        readingValues: jsonEncode(values),
      );

      state = state.copyWith(isLoading: false, success: true);
      ref.invalidate(adminDashboardStatsProvider);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to edit reading: $e');
    }
  }
}

final adminReadingFormNotifierProvider =
    NotifierProvider.autoDispose<AdminReadingFormNotifier, AdminReadingFormState>(
        AdminReadingFormNotifier.new);
