import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../domain/usecases/validate_heat_number_usecase.dart';

/// Provider for [ValidateHeatNumberUseCase].
final validateHeatNumberUseCaseProvider = Provider<ValidateHeatNumberUseCase>((ref) {
  return ValidateHeatNumberUseCase(ref.watch(supabaseReadingsRepoProvider));
});

/// Family provider that validates a heat number for a given device.
/// Returns [HeatValidationResult] — check `.isValid` and `.error`.
///
/// Usage:
///   final result = ref.watch(heatValidationProvider((deviceId: id, heatNumber: text)));
final heatValidationProvider = FutureProvider.family<HeatValidationResult, ({String deviceId, String heatNumber})>(
  (ref, params) async {
    if (params.heatNumber.trim().isEmpty) {
      return HeatValidationResult.valid;
    }
    final useCase = ref.read(validateHeatNumberUseCaseProvider);
    return useCase.call(
      deviceId: params.deviceId,
      heatNumberText: params.heatNumber,
    );
  },
);
