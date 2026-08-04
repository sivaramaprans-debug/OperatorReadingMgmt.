import 'dart:convert';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../../../database/supabase_client.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';

class EditReadingUseCase {
  const EditReadingUseCase({required this.readingsRepo});
  final SupabaseReadingsRepository readingsRepo;

  Future<(bool, Failure?)> call({
    required String operatorId,
    required String readingId,
    required String readingType,
    required String heatNumber,
    required Map<String, double> values,
  }) async {
    if (values.isEmpty) {
      return (false, const ValidationFailure('At least one reading value is required.'));
    }

    final finalHeatNumber =
        (readingType == 'day' || readingType == 'standard') ? '' : heatNumber.trim();
    if (readingType == 'heat' && finalHeatNumber.isEmpty) {
      return (false, const ValidationFailure('Heat Number is required for Heat readings.'));
    }

    for (final entry in values.entries) {
      if (entry.value < 0) {
        return (false, ValidationFailure('Value for ${entry.key} cannot be negative.'));
      }
    }

    try {
      // Fetch all readings for this operator and find by id
      final allReadings = await readingsRepo.getForOperator(operatorId, limit: 500);
      final existing = allReadings.where((r) => r.id == readingId).firstOrNull;
      if (existing == null) {
        return (false, const NotFoundFailure('Reading not found.'));
      }

      if (existing.operatorId != operatorId) {
        return (false, const ValidationFailure('You do not have permission to edit this reading.'));
      }

      final todayMidnight = AppDateUtils.todayLocalMidnightUtcMs();
      if (existing.readingDate != todayMidnight) {
        return (false, const ValidationFailure('Readings can only be edited on the day they were created.'));
      }

      if (existing.readingType != readingType || existing.heatNumber != finalHeatNumber) {
        final isDuplicate = await readingsRepo.existsDuplicate(
          deviceId: existing.deviceId,
          readingDateMs: todayMidnight,
          readingType: readingType,
          heatNumber: finalHeatNumber,
          excludeId: readingId,
        );
        if (isDuplicate) {
          return (false, const ValidationFailure('A reading with this Type/Heat already exists today.'));
        }
      }

      final valuesJson = jsonEncode(values);
      await supabase.from('readings').update({
        'reading_type': readingType,
        'heat_number': finalHeatNumber,
        'reading_values': valuesJson,
      }).eq('id', readingId);

      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Failed to edit reading: $e'));
    }
  }
}
