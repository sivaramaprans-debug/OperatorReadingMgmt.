import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_reading_mgmt/core/utils/reading_calculation_utils.dart';
import 'package:operator_reading_mgmt/database/repositories/supabase_meter_replacement_repository.dart';

void main() {
  group('ReadingCalculationUtils - Direct Factors (No Replacements)', () {
    test('resolves day factor directly when edited on device', () {
      final factor = ReadingCalculationUtils.resolveEffectiveFactor(
        readingDateMs: 1725532800000,
        unit: 'KWH',
        currentDeviceMf: 1.0,
        dayUnitFactorsJson: jsonEncode({'KWH': 12.0}),
        heatUnitFactorsJson: '{}',
        replacements: const [],
      );
      expect(factor, 12.0);
    });

    test('falls back to currentDeviceMf if day factor is missing', () {
      final factor = ReadingCalculationUtils.resolveEffectiveFactor(
        readingDateMs: 1725532800000,
        unit: 'KWH',
        currentDeviceMf: 20.0,
        dayUnitFactorsJson: '{}',
        heatUnitFactorsJson: '{}',
        replacements: const [],
      );
      expect(factor, 20.0);
    });

    test('calculates diff and consumption correctly with direct factor', () {
      final res = ReadingCalculationUtils.calculateReadingConsumption(
        currentReading: 110.0,
        currentDateMs: 1725532800000,
        prevReading: 100.0,
        prevDateMs: 1725446400000,
        unit: 'KWH',
        currentDeviceMf: 12.0,
        dayUnitFactorsJson: jsonEncode({'KWH': 12.0}),
        heatUnitFactorsJson: '{}',
      );
      expect(res.diff, 10.0);
      expect(res.consumption, 120.0);
      expect(res.factor, 12.0);
    });
  });

  group('ReadingCalculationUtils - Meter Replacement Events', () {
    final replacement = SupabaseMeterReplacement(
      id: 'rep-1',
      deviceId: 'dev-1',
      replacementDate: 1725500000000, // Changeover at timestamp T
      businessDayMs: 1725494400000,
      oldMeterFinalValues: jsonEncode({'KWH': 1000.0}),
      oldMeterFactors: jsonEncode({'KWH': 10.0}), // Old MF was 10.0
      newMeterInitialValues: jsonEncode({'KWH': 0.0}),
      newMeterFactors: jsonEncode({'KWH': 25.0}), // New MF is 25.0
      createdAt: 1725500000000,
    );

    test('reading BEFORE replacement date uses historical old factor', () {
      final factor = ReadingCalculationUtils.resolveEffectiveFactor(
        readingDateMs: 1725400000000, // Prior to replacement
        unit: 'KWH',
        currentDeviceMf: 25.0,
        dayUnitFactorsJson: jsonEncode({'KWH': 25.0}),
        heatUnitFactorsJson: '{}',
        replacements: [replacement],
      );
      expect(factor, 10.0);
    });

    test('reading ON OR AFTER replacement date uses new factor', () {
      final factor = ReadingCalculationUtils.resolveEffectiveFactor(
        readingDateMs: 1725600000000, // After replacement
        unit: 'KWH',
        currentDeviceMf: 25.0,
        dayUnitFactorsJson: jsonEncode({'KWH': 25.0}),
        heatUnitFactorsJson: '{}',
        replacements: [replacement],
      );
      expect(factor, 25.0);
    });

    test('calculates transition consumption spanning meter replacement correctly', () {
      // Prev reading: 950.0 on old meter (at 1725400000000)
      // Replacement occurred at 1725500000000 (old final = 1000.0, factor = 10; new initial = 0.0, factor = 25)
      // Current reading: 50.0 on new meter (at 1725600000000)
      final res = ReadingCalculationUtils.calculateReadingConsumption(
        currentReading: 50.0,
        currentDateMs: 1725600000000,
        prevReading: 950.0,
        prevDateMs: 1725400000000,
        unit: 'KWH',
        currentDeviceMf: 25.0,
        dayUnitFactorsJson: jsonEncode({'KWH': 25.0}),
        heatUnitFactorsJson: '{}',
        replacements: [replacement],
      );

      // Old portion: (1000 - 950) * 10 = 50 * 10 = 500
      // New portion: (50 - 0) * 25 = 50 * 25 = 1250
      // Total consumption = 500 + 1250 = 1750
      expect(res.consumption, 1750.0);
      expect(res.factor, 25.0);
    });
  });
}
