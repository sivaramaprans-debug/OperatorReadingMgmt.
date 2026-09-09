import 'dart:convert';
import 'package:intl/intl.dart';
import '../../database/repositories/supabase_meter_replacement_repository.dart';

/// Calculation engine for difference, rollover detection, and meter replacement transitions.
class ReadingCalculationUtils {
  /// Automatic Rollover Difference:
  /// Computes (current - prev).
  /// If current < prev, detects meter rollover capacity (e.g. 10^6 for 6 digits, 10^7, 10^8)
  /// and returns the true rollover difference.
  static double calculateDifference(double current, double prev) {
    if (current >= prev) {
      return current - prev;
    }

    // Rollover detection: find nearest power of 10 strictly > prev
    // e.g. prev = 998,999 -> capacity = 1,000,000 (10^6)
    // e.g. prev = 9,850,000 -> capacity = 10,000,000 (10^7)
    double capacity = 10.0;
    while (capacity <= prev) {
      capacity *= 10.0;
    }

    final diff = (capacity - prev) + current;
    // Check if rollover diff is plausible (e.g. less than half capacity)
    if (diff >= 0 && diff < capacity) {
      return diff;
    }

    return current - prev;
  }

  /// Parses JSON reading values safely into Map<String, double>
  static Map<String, double> parseValues(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  /// Parses JSON factor map safely into Map<String, double>
  static Map<String, double> parseFactors(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  /// Resolves the effective Multiplication Factor (MF) for a reading given its date,
  /// unit/metric, and the device's configuration and meter replacement history.
  ///
  /// Priority:
  /// 1. If meter replacements exist, resolves historical factor according to [readingDateMs].
  /// 2. If no replacements apply: checks dayUnitFactors, heatUnitFactors, then currentDeviceMf.
  static double resolveEffectiveFactor({
    required int readingDateMs,
    required String unit,
    String readingType = 'day',
    required double currentDeviceMf,
    required String dayUnitFactorsJson,
    required String heatUnitFactorsJson,
    List<SupabaseMeterReplacement> replacements = const [],
  }) {
    // 1. Check meter replacement history
    if (replacements.isNotEmpty) {
      final sortedReps = List<SupabaseMeterReplacement>.from(replacements)
        ..sort((a, b) => a.replacementDate.compareTo(b.replacementDate));

      // If reading is strictly before the first recorded meter replacement:
      if (readingDateMs < sortedReps.first.replacementDate) {
        final oldFactors = sortedReps.first.parsedOldFactors;
        final f = oldFactors[unit] ?? oldFactors[unit.toUpperCase()];
        if (f != null && f > 0) return f;
      }

      // If reading is between replacements R_i and R_{i+1}:
      for (int i = 0; i < sortedReps.length - 1; i++) {
        final rCur = sortedReps[i];
        final rNext = sortedReps[i + 1];
        if (readingDateMs >= rCur.replacementDate && readingDateMs < rNext.replacementDate) {
          final newFactors = rCur.parsedNewFactors;
          final f = newFactors[unit] ?? newFactors[unit.toUpperCase()] ?? rNext.parsedOldFactors[unit];
          if (f != null && f > 0) return f;
        }
      }

      // If reading is on or after the latest replacement:
      final latestRep = sortedReps.last;
      if (readingDateMs >= latestRep.replacementDate) {
        final newFactors = latestRep.parsedNewFactors;
        final f = newFactors[unit] ?? newFactors[unit.toUpperCase()];
        if (f != null && f > 0) return f;
      }
    }

    // 2. Direct device factor resolution (no meter replacements or outside range)
    final dayFactors = parseFactors(dayUnitFactorsJson);
    final heatFactors = parseFactors(heatUnitFactorsJson);

    final upperUnit = unit.toUpperCase();
    if (readingType == 'heat') {
      final hf = heatFactors[unit] ?? heatFactors[upperUnit];
      if (hf != null && hf > 0) return hf;
      final df = dayFactors[unit] ?? dayFactors[upperUnit];
      if (df != null && df > 0) return df;
    } else {
      final df = dayFactors[unit] ?? dayFactors[upperUnit];
      if (df != null && df > 0) return df;
      final hf = heatFactors[unit] ?? heatFactors[upperUnit];
      if (hf != null && hf > 0) return hf;
    }

    if (currentDeviceMf > 0) return currentDeviceMf;
    return 1.0;
  }

  /// Calculates reading difference and consumption for a reading.
  /// Automatically handles meter replacements that occurred between [prevDateMs] and [currentDateMs].
  static ({double? diff, double? consumption, double factor}) calculateReadingConsumption({
    required double currentReading,
    required int currentDateMs,
    required double? prevReading,
    required int? prevDateMs,
    required String unit,
    String readingType = 'day',
    required double currentDeviceMf,
    required String dayUnitFactorsJson,
    required String heatUnitFactorsJson,
    List<SupabaseMeterReplacement> replacements = const [],
  }) {
    final curFactor = resolveEffectiveFactor(
      readingDateMs: currentDateMs,
      unit: unit,
      readingType: readingType,
      currentDeviceMf: currentDeviceMf,
      dayUnitFactorsJson: dayUnitFactorsJson,
      heatUnitFactorsJson: heatUnitFactorsJson,
      replacements: replacements,
    );

    if (prevReading == null || prevDateMs == null) {
      return (diff: null, consumption: null, factor: curFactor);
    }

    // Check if a meter replacement occurred between prevDateMs and currentDateMs
    SupabaseMeterReplacement? transitionRep;
    if (replacements.isNotEmpty) {
      final sortedReps = List<SupabaseMeterReplacement>.from(replacements)
        ..sort((a, b) => a.replacementDate.compareTo(b.replacementDate));

      for (final rep in sortedReps) {
        if (rep.replacementDate > prevDateMs && rep.replacementDate <= currentDateMs) {
          transitionRep = rep;
          break;
        }
      }
    }

    if (transitionRep != null) {
      // Meter was physically replaced between previous and current reading!
      final oldFinal = transitionRep.parsedOldFinalValues[unit] ??
          transitionRep.parsedOldFinalValues[unit.toUpperCase()] ??
          prevReading;
      final oldFactor = transitionRep.parsedOldFactors[unit] ??
          transitionRep.parsedOldFactors[unit.toUpperCase()] ??
          resolveEffectiveFactor(
            readingDateMs: prevDateMs,
            unit: unit,
            readingType: readingType,
            currentDeviceMf: currentDeviceMf,
            dayUnitFactorsJson: dayUnitFactorsJson,
            heatUnitFactorsJson: heatUnitFactorsJson,
            replacements: replacements,
          );

      final newInitial = transitionRep.parsedNewInitialValues[unit] ??
          transitionRep.parsedNewInitialValues[unit.toUpperCase()] ??
          0.0;
      final newFactor = curFactor;

      final oldDiff = calculateDifference(oldFinal, prevReading);
      final oldCons = oldDiff * oldFactor;

      final newDiff = calculateDifference(currentReading, newInitial);
      final newCons = newDiff * newFactor;

      final totalCons = oldCons + newCons;
      final totalDiff = newFactor > 0 ? (totalCons / newFactor) : (currentReading - prevReading);

      return (diff: totalDiff, consumption: totalCons, factor: newFactor);
    }

    // Standard reading step (on same meter)
    final diff = calculateDifference(currentReading, prevReading);
    final cons = diff * curFactor;
    return (diff: diff, consumption: cons, factor: curFactor);
  }
}

