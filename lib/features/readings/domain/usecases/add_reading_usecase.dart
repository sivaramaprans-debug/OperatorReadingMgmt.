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

    final normalizedHeat = (heatNumber.trim().toUpperCase() == 'R/F' || heatNumber.trim().toUpperCase() == 'RF')
        ? 'R/F'
        : heatNumber.trim();
    final finalHeatNumber =
        (readingType == 'day' || readingType == 'standard') ? '' : normalizedHeat;
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

      // ── Zero-Difference / Identical Meter Values Safeguard ──────────────────
      final prevReading = await readingsRepo.getPreviousReading(
        deviceId: deviceId,
        readingType: readingType,
        readingDateMs: targetDate,
        heatNumber: finalHeatNumber,
      );

      if (prevReading != null) {
        try {
          final prevVals = (jsonDecode(prevReading.readingValues) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k.toUpperCase(), (v as num).toDouble()));

          const cumulativeUnits = ['KWH', 'KWHLT', 'KVAH', 'KVARH', 'LTRS'];
          final presentCumulative = values.keys
              .where((k) => cumulativeUnits.contains(k.toUpperCase()))
              .toList();

          if (presentCumulative.isNotEmpty) {
            bool allIdentical = true;
            for (final u in presentCumulative) {
              final curVal = values[u]!;
              final prevVal = prevVals[u.toUpperCase()];
              if (prevVal == null || (curVal - prevVal).abs() > 0.0001) {
                allIdentical = false;
                break;
              }
            }

            if (allIdentical) {
              return (
                null,
                const ValidationFailure(
                  'This reading has identical meter values to the previous reading (0 difference). Duplicate entry not allowed.',
                ),
              );
            }
          }
        } catch (_) {}
      }

      // ── Immediate Consecutive Duplicate Heat Check ────────────────────────
      // Same heat number cannot be entered one after another. Subsequent cycles
      // in the 24h day (e.g. 1-6 and later 1-6) are fully permitted.
      if (readingType == 'heat' && finalHeatNumber != 'R/F') {
        final lastNumbered = await readingsRepo.getLastNumberedHeatReading(deviceId: deviceId);
        if (lastNumbered != null && lastNumbered.heatNumber.trim() == finalHeatNumber) {
          return (
            null,
            ValidationFailure(
              'Heat #$finalHeatNumber was already the last recorded heat. Duplicate consecutive heat reading not allowed.',
            ),
          );
        }
      }

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
