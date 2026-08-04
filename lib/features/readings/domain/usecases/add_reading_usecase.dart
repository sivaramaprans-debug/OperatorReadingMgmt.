import 'dart:convert';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';

class AddReadingUseCase {
  const AddReadingUseCase({
    required this.devicesRepo,
    required this.readingsRepo,
  });
  final SupabaseDevicesRepository devicesRepo;
  final SupabaseReadingsRepository readingsRepo;

  Future<(String?, Failure?)> call({
    required String operatorId,
    required String deviceId,
    required String readingType,
    required String heatNumber,
    required Map<String, double> values,
    int? readingDate,
  }) async {
    if (values.isEmpty)
      return (null, const ValidationFailure('At least one reading value is required.'));

    final validTypes = ['day', 'heat', 'standard'];
    if (!validTypes.contains(readingType)) {
      return (null, const ValidationFailure('Invalid reading type.'));
    }

    final finalHeatNumber =
        (readingType == 'day' || readingType == 'standard') ? '' : heatNumber.trim();
    if (readingType == 'heat' && finalHeatNumber.isEmpty) {
      return (null, const ValidationFailure('Heat Number is required for Heat readings.'));
    }

    for (final entry in values.entries) {
      if (entry.value < 0) {
        return (null, ValidationFailure('Value for ${entry.key} cannot be negative.'));
      }
    }

    try {
      final device = await devicesRepo.findById(deviceId);
      if (device == null || !device.isActive) {
        return (null, const ValidationFailure('Selected device is unavailable.'));
      }

      // Validate units against device matrix
      final deviceUnits = (readingType == 'day' || !device.requiresHeatDay)
          ? (device.dayMatrix.isEmpty
              ? (device.matrix.isEmpty ? <String>[] : device.matrix.split(',').map((e) => e.trim()).toList())
              : device.dayMatrix.split(',').map((e) => e.trim()).toList())
          : (device.matrix.isEmpty
              ? <String>[]
              : device.matrix.split(',').map((e) => e.trim()).toList());
      if (deviceUnits.isNotEmpty) {
        for (final unit in values.keys) {
          if (!deviceUnits.contains(unit)) {
            return (null, ValidationFailure(
                'Unit "$unit" is not assigned to this device for $readingType readings.'));
          }
        }
      }

      if (readingType == 'heat' && !device.requiresHeatDay) {
        return (null, const ValidationFailure('This device does not support Heat readings.'));
      }

      final targetDate = readingDate ?? AppDateUtils.todayLocalMidnightUtcMs();

      final isDuplicate = await readingsRepo.existsDuplicate(
        deviceId: deviceId,
        readingDateMs: targetDate,
        readingType: readingType,
        heatNumber: finalHeatNumber,
      );

      if (isDuplicate) {
        if (readingType == 'day' || readingType == 'standard') {
          return (null, const ValidationFailure('A reading already exists for this device on the selected date/time.'));
        } else {
          return (null, ValidationFailure(
              'A reading for Heat "$finalHeatNumber" already exists on the selected date/time.'));
        }
      }

      final valuesJson = jsonEncode(values);
      final id = await readingsRepo.insert(
        operatorId: operatorId,
        deviceId: deviceId,
        readingDate: targetDate,
        readingType: readingType,
        heatNumber: finalHeatNumber,
        readingValues: valuesJson,
      );
      return (id, null);
    } catch (e) {
      return (null, DatabaseFailure('Failed to save reading: $e'));
    }
  }
}
