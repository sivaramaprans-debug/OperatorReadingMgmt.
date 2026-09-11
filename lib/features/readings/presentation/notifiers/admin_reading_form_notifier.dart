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
      
      final clean = heatNumber.trim().toUpperCase();
      final normalizedHeat = (clean == 'R/F' || clean == 'RF') ? 'R/F' : heatNumber.trim();
      final finalHeatNumber =
          (readingType == 'day' || readingType == 'standard') ? '' : normalizedHeat;

      // Safeguard against duplicate identical meter readings
      final prevReading = await repo.getPreviousReading(
        deviceId: deviceId,
        readingType: readingType,
        readingDateMs: readingDate,
        heatNumber: finalHeatNumber,
      );

      if (prevReading != null) {
        try {
          final prevVals = (jsonDecode(prevReading.readingValues) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k.toUpperCase(), (v as num).toDouble()));

          const cumulativeUnits = ['KWH', 'KWHLT', 'KVAH', 'KVARH', 'LTRS'];
          final present = values.keys.where((k) => cumulativeUnits.contains(k.toUpperCase())).toList();

          if (present.isNotEmpty) {
            bool allIdentical = true;
            for (final u in present) {
              final curVal = values[u]!;
              final prevVal = prevVals[u.toUpperCase()];
              if (prevVal == null || (curVal - prevVal).abs() > 0.0001) {
                allIdentical = false;
                break;
              }
            }

            if (allIdentical) {
              state = state.copyWith(
                isLoading: false,
                error: 'This reading has identical meter values to the previous reading (0 difference). Duplicate entry not allowed.',
              );
              return;
            }
          }
        } catch (_) {}
      }

      // Check if heat number already exists in current business cycle
      if (readingType == 'heat') {
        final heatInBizDay = await repo.existsHeatNumberInBusinessDay(
          deviceId: deviceId,
          heatNumber: finalHeatNumber,
          readingDateMs: readingDate,
        );
        if (heatInBizDay) {
          state = state.copyWith(
            isLoading: false,
            error: 'A reading for Heat "$finalHeatNumber" already exists in the current business cycle.',
          );
          return;
        }
      }
          
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
