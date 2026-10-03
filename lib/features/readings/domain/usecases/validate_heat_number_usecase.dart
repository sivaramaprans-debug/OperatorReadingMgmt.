import '../../../../database/repositories/supabase_readings_repository.dart';

/// Result of heat number validation.
class HeatValidationResult {
  const HeatValidationResult._({
    this.error,
    this.expectedNext,
    this.canSwitchover = false,
  });

  /// Null means the proposed heat number is valid.
  final String? error;

  /// What the system expects the next heat number to be (for UI hint).
  final int? expectedNext;

  /// Whether this validation failure can be resolved via Crucible Switchover.
  final bool canSwitchover;

  bool get isValid => error == null;

  static const HeatValidationResult valid = HeatValidationResult._();

  factory HeatValidationResult.invalid(
    String message, {
    int? expectedNext,
    bool canSwitchover = false,
  }) =>
      HeatValidationResult._(
        error: message,
        expectedNext: expectedNext,
        canSwitchover: canSwitchover,
      );
}

/// Validates a proposed heat number against all business rules:
///
/// R1 + R2: next = prev + 1 OR R/F
/// R3: New cycle starts from Heat 1 (when previous heat is not 1)
/// R4: Same heat number cannot be entered consecutively one after another
/// R5: Crucible Switchover mode allows entering any heat number (resuming alternate crucible after breakdown)
class ValidateHeatNumberUseCase {
  const ValidateHeatNumberUseCase(this._repo);
  final SupabaseReadingsRepository _repo;

  Future<HeatValidationResult> call({
    required String deviceId,
    required String heatNumberText,
    bool isCrucibleSwitchover = false,
  }) async {
    // Fetch the most recent numbered heat reading (ignoring R/F) to determine expectedNext
    final lastNumberedReading = await _repo.getLastNumberedHeatReading(deviceId: deviceId);
    final lastReading = await _repo.getLastHeatReading(deviceId: deviceId);
    final prevHeat = lastNumberedReading != null ? int.tryParse(lastNumberedReading.heatNumber.trim()) : null;
    final expectedNext = (prevHeat != null) ? (prevHeat + 1) : 1;

    final trimmed = heatNumberText.trim();
    if (trimmed.isEmpty) {
      return HeatValidationResult._(error: null, expectedNext: expectedNext);
    }

    // ── Re-Furnace (R/F) check ────────────────────────────────────────────────
    if (trimmed.toUpperCase() == 'R/F' || trimmed.toUpperCase() == 'RF') {
      return HeatValidationResult._(error: null, expectedNext: expectedNext);
    }

    final proposed = int.tryParse(trimmed);
    if (proposed == null || proposed < 1) {
      return HeatValidationResult.invalid(
        'Heat number must be a positive integer or "R/F" for Re-Furnace.',
        expectedNext: expectedNext,
      );
    }

    // ── No previous reading: only Heat #1 is allowed ──────────────────────────
    if (lastReading == null) {
      if (proposed == 1) return HeatValidationResult.valid;
      return HeatValidationResult.invalid(
        'No previous heat readings found. The first heat number must be 1.',
        expectedNext: 1,
      );
    }

    // ── Crucible Switchover Mode (Breakdown / Maintenance Transition) ─────────
    if (isCrucibleSwitchover) {
      // In switchover mode, operator can enter any heat number to start or resume
      // the alternate crucible (e.g. 1 to start standby, or 2, 5, 6 to resume).
      // Only protect against immediate consecutive duplicate of the exact previous reading.
      if (lastReading.heatNumber.trim() == proposed.toString()) {
        return HeatValidationResult.invalid(
          'Heat #$proposed was already the last recorded heat. '
          'Consecutive duplicate heat numbers are not allowed.',
          expectedNext: expectedNext,
        );
      }
      return HeatValidationResult.valid;
    }

    if (prevHeat == null) {
      // Corrupted previous data — only allow heat 1 as a safe fallback
      if (proposed == 1) return HeatValidationResult.valid;
      return HeatValidationResult.invalid(
        'Previous heat number is invalid. Please start a new cycle with Heat #1, or enable Crucible Switchover.',
        expectedNext: 1,
        canSwitchover: true,
      );
    }

    // ── Case 1: consecutive continuation ──────────────────────────────────────
    if (proposed == expectedNext) {
      return HeatValidationResult.valid;
    }

    // ── Case 2: new cycle / crucible switchover (proposed == 1) ───────────────
    if (proposed == 1) {
      if (prevHeat == 1) {
        // Can only happen if Crucible 1 stopped at Heat 1 and switched to Crucible 2.
        // In plant operation, crucible switchover and heat cycle takes minimum 6 hours.
        final lastTime = DateTime.fromMillisecondsSinceEpoch(
          lastNumberedReading!.readingDate,
          isUtc: true,
        );
        final elapsed = DateTime.now().toUtc().difference(lastTime);
        if (elapsed.inHours < 6) {
          return HeatValidationResult.invalid(
            'Heat #1 was already the last recorded heat. '
            'Immediate duplicate Heat #1 is not allowed.\n'
            'A new crucible cycle can only be recorded after a minimum 6-hour gap.',
            expectedNext: expectedNext,
          );
        }
      }
      return HeatValidationResult.valid;
    }

    // ── Case 3: duplicate of immediate previous heat ──────────────────────────
    if (proposed == prevHeat) {
      return HeatValidationResult.invalid(
        'Heat #$proposed was already the last recorded heat. '
        'Next heat must be Heat #$expectedNext, or enter "R/F" for Re-furnace.',
        expectedNext: expectedNext,
      );
    }

    // ── Case 4: out-of-order sequence (eligible for Crucible Switchover) ──────
    return HeatValidationResult.invalid(
      'Out of sequence. After Heat #$prevHeat, you must enter Heat #$expectedNext, "R/F", or "1".\n'
      'If switching or resuming crucibles due to breakdown, enable Crucible Switchover.',
      expectedNext: expectedNext,
      canSwitchover: true,
    );
  }
}
