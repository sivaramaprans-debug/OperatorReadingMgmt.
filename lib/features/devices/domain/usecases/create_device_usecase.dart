import 'dart:convert';
import '../../../../core/errors/failures.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';

class CreateDeviceUseCase {
  const CreateDeviceUseCase({required this.devicesRepo});
  final SupabaseDevicesRepository devicesRepo;

  Future<(String?, Failure?)> call({
    required String adminId,
    required String name,
    required double factor,
    required List<String> matrix,
    required List<String> dayMatrix,
    required bool requiresHeatDay,
    Map<String, double> heatUnitFactors = const {},
    Map<String, double> dayUnitFactors = const {},
    String deviceCategory = DeviceCategory.energy,
  }) async {
    if (name.trim().isEmpty) return (null, const ValidationFailure('Device name is required.'));

    try {
      final matrixStr = matrix.join(',');
      final dayMatrixStr = dayMatrix.join(',');
      final heatFactorsJson = jsonEncode(heatUnitFactors);
      final dayFactorsJson = jsonEncode(dayUnitFactors);

      final id = await devicesRepo.create(
        name: name.trim(),
        multiplicationFactor: factor,
        matrix: matrixStr,
        dayMatrix: dayMatrixStr,
        requiresHeatDay: requiresHeatDay,
        heatUnitFactors: heatFactorsJson,
        dayUnitFactors: dayFactorsJson,
        deviceCategory: deviceCategory,
      );
      return (id, null);
    } catch (e) {
      return (null, DatabaseFailure('Failed to create device: $e'));
    }
  }
}
