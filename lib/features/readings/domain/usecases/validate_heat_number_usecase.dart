import '../../../../core/utils/app_date_utils.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';

/// Result of heat number validation.
class HeatValidationResult {
  const HeatValidationResult._({this.error, this.expectedNext});

  /// Null means the proposed heat number is valid.
  final String? error;

  /// What the system expects the next heat number to be (for UI hint).
  final int? expectedNext;

  bool get isValid => error == null;

  static const HeatValidationResult valid = HeatValidationResult._();

  factory HeatValidationResult.invalid(String message, {int? expectedNext}) =>
      HeatValidationResult._(error: message, expectedNext: expectedNext);
}

/// Validates a proposed heat number against all business rules:
///
/// R1 + R2 + R5: next = prev + 1 OR next = 1 (combined into one check)
/// R3: New cycle always starts from 1
/// R4: Heat #1 on the same calendar day requires ≥10 hours since the last Heat #1
class ValidateHeatNumberUseCase {
  const ValidateHeatNumberUseCase(this._repo);
  final SupabaseReadingsRepository _repo;

  static const int _minCycleGapHours = 10;

  Future<HeatValidationResult> call({
    required String deviceId,
    required String heatNumberText,
  }) async {
    final proposed = int.tryParse(heatNumberText.trim());
    if (proposed == null || proposed < 1) {
      return HeatValidationResult.invalid('Heat number must be a positive integer.');
    }

    // Fetch the most recent heat reading for this device (regardless of date)
    final lastReading = await _repo.getLastHeatReading(deviceId: deviceId);

    // ── No previous reading: only Heat #1 is allowed ──────────────────────────
    if (lastReading == null) {
      if (proposed == 1) return HeatValidationResult.valid;
      return HeatValidationResult.invalid(
        'No previous heat readings found. The first heat number must be 1.',
        expectedNext: 1,
      );
    }

    final prevHeat = int.tryParse(lastReading.heatNumber.trim());
    if (prevHeat == null) {
      // Corrupted previous data — only allow heat 1 as a safe fallback
      if (proposed == 1) return HeatValidationResult.valid;
      return HeatValidationResult.invalid(
        'Previous heat number is invalid. Please start a new cycle with Heat #1.',
        expectedNext: 1,
      );
    }

    final expectedNext = prevHeat + 1;

    // ── Case 1: consecutive continuation ──────────────────────────────────────
    if (proposed == expectedNext) {
      return HeatValidationResult.valid;
    }

    // ── Case 2: new cycle (proposed == 1) ─────────────────────────────────────
    if (proposed == 1) {
      final todayMidnight = AppDateUtils.todayLocalMidnightUtcMs();
      final lastHeat1 = await _repo.getLastHeatNumberOneOnDate(
        deviceId: deviceId,
        dayMidnightMs: todayMidnight,
      );

      // No Heat #1 on today — freely allowed
      if (lastHeat1 == null) return HeatValidationResult.valid;

      // Check 10-hour gap
      final lastHeat1Time = DateTime.fromMillisecondsSinceEpoch(
        lastHeat1.createdAt,
        isUtc: true,
      );
      final now = DateTime.now().toUtc();
      final elapsed = now.difference(lastHeat1Time);

      if (elapsed.inHours >= _minCycleGapHours) {
        return HeatValidationResult.valid;
      }

      // Too soon — tell the operator when they can start the next cycle
      final canStartAt = lastHeat1Time.add(const Duration(hours: _minCycleGapHours)).toLocal();
      final hh = canStartAt.hour.toString().padLeft(2, '0');
      final mm = canStartAt.minute.toString().padLeft(2, '0');
      return HeatValidationResult.invalid(
        'A new heat cycle can only start after 10 hours from the last Heat #1.\n'
        'Next cycle can start at $hh:$mm today.',
        expectedNext: expectedNext,
      );
    }

    // ── Case 3: anything else (skipped, repeated, out-of-order) ───────────────
    if (proposed == prevHeat) {
      return HeatValidationResult.invalid(
        'Heat #$proposed was already the last reading. '
        'Next heat must be $expectedNext, or start a new cycle with Heat #1.',
        expectedNext: expectedNext,
      );
    }

    return HeatValidationResult.invalid(
      'Invalid heat number. After Heat #$prevHeat, '
      'you must enter Heat #$expectedNext, or start a new cycle with Heat #1.',
      expectedNext: expectedNext,
    );
  }
}
