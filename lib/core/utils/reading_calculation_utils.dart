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
}
