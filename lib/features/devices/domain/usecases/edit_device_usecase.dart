import 'dart:convert';
import '../../../../core/errors/failures.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';

class EditDeviceUseCase {
  const EditDeviceUseCase({required this.devicesRepo});
  final SupabaseDevicesRepository devicesRepo;

  Future<(bool, Failure?)> call({
    required String adminId,
    required String deviceId,
    required String name,
    required double factor,
    required List<String> matrix,
    required List<String> dayMatrix,
    required bool requiresHeatDay,
    Map<String, double> heatUnitFactors = const {},
    Map<String, double> dayUnitFactors = const {},
  }) async {
    if (name.trim().isEmpty) return (false, const ValidationFailure('Device name is required.'));

    try {
      await devicesRepo.update(
        deviceId,
        name: name.trim(),
        multiplicationFactor: factor,
        matrix: matrix.join(','),
        dayMatrix: dayMatrix.join(','),
        requiresHeatDay: requiresHeatDay,
        heatUnitFactors: jsonEncode(heatUnitFactors),
        dayUnitFactors: jsonEncode(dayUnitFactors),
      );
      return (true, null);
    } catch (e) {
      return (false, DatabaseFailure('Failed to edit device: $e'));
    }
  }
}
