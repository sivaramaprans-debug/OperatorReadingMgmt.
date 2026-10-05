import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_reading_mgmt/core/utils/app_date_utils.dart';
import 'package:operator_reading_mgmt/database/repositories/supabase_devices_repository.dart';
import 'package:operator_reading_mgmt/database/repositories/supabase_meter_replacement_repository.dart';
import 'package:operator_reading_mgmt/database/repositories/supabase_operators_repository.dart';
import 'package:operator_reading_mgmt/database/repositories/supabase_readings_repository.dart';
import 'package:operator_reading_mgmt/features/readings/domain/usecases/export_readings_usecase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExportMonthlyReportUseCase - Excel Workbook Generation', () {
    late List<SupabaseDevice> devices;
    late List<SupabaseOperator> operators;
    late List<Map<String, dynamic>> activeAssignments;
    late List<SupabaseReadingWithDetails> readings;
    late List<SupabaseMeterReplacement> replacements;

    setUp(() {
      // 1. Devices
      devices = [
        // Energy devices
        const SupabaseDevice(
          id: 'dev-132kv',
          name: '132kv',
          multiplicationFactor: 200000.0,
          matrix: 'KWH,KWHLT,KVAH,PF',
          dayMatrix: 'KWH,KWHLT,KVAH,PF',
          requiresHeatDay: false,
          heatUnitFactors: '{}',
          dayUnitFactors: '{"KWH": 200000.0, "KWHLT": 200000.0, "KVAH": 200000.0}',
          isActive: true,
          createdAt: 1000,
          deviceCategory: DeviceCategory.energy,
        ),
        const SupabaseDevice(
          id: 'dev-sid',
          name: 'SID',
          multiplicationFactor: 1000.0,
          matrix: 'KWH,KWHLT',
          dayMatrix: 'KWH,KWHLT',
          requiresHeatDay: false,
          heatUnitFactors: '{}',
          dayUnitFactors: '{"KWH": 1000.0, "KWHLT": 1000.0}',
          isActive: true,
          createdAt: 1000,
          deviceCategory: DeviceCategory.energy,
        ),
        const SupabaseDevice(
          id: 'dev-sms2-fur',
          name: 'SMS2',
          multiplicationFactor: 80.0,
          matrix: 'KWH,KWHLT',
          dayMatrix: 'KWH,KWHLT,KVAH,PF',
          requiresHeatDay: true,
          heatUnitFactors: '{"KWH": 80.0, "KWHLT": 80.0}',
          dayUnitFactors: '{"KWH": 80.0, "KWHLT": 80.0, "KVAH": 80.0}',
          isActive: true,
          createdAt: 1000,
          deviceCategory: DeviceCategory.energy,
        ),
        const SupabaseDevice(
          id: 'dev-sms2-fan1',
          name: 'SMS 2 ID FAN 1',
          multiplicationFactor: 1.0,
          matrix: 'KWH',
          dayMatrix: 'KWH',
          requiresHeatDay: false,
          heatUnitFactors: '{}',
          dayUnitFactors: '{"KWH": 1.0}',
          isActive: true,
          createdAt: 1000,
          deviceCategory: DeviceCategory.energy,
        ),
        // Dedusting devices
        const SupabaseDevice(
          id: 'dev-cooler-dd1',
          name: 'COOLER DD 1',
          multiplicationFactor: 1.0,
          matrix: 'KWH',
          dayMatrix: 'KWH',
          requiresHeatDay: false,
          heatUnitFactors: '{}',
          dayUnitFactors: '{"KWH": 1.0}',
          isActive: true,
          createdAt: 1000,
          deviceCategory: DeviceCategory.dedusting,
        ),
        // Water devices
        const SupabaseDevice(
          id: 'dev-sid-process',
          name: 'SID PROCESS',
          multiplicationFactor: 1.0,
          matrix: 'LTRS',
          dayMatrix: 'LTRS',
          requiresHeatDay: false,
          heatUnitFactors: '{}',
          dayUnitFactors: '{"LTRS": 1.0}',
          isActive: true,
          createdAt: 1000,
          deviceCategory: DeviceCategory.water,
        ),
        const SupabaseDevice(
          id: 'dev-rmd-water',
          name: 'RMD water',
          multiplicationFactor: 1.0,
          matrix: 'LTRS',
          dayMatrix: 'LTRS',
          requiresHeatDay: false,
          heatUnitFactors: '{}',
          dayUnitFactors: '{"LTRS": 1.0}',
          isActive: true,
          createdAt: 1000,
          deviceCategory: DeviceCategory.water,
        ),
      ];

      // 2. Operators
      operators = [
        const SupabaseOperator(
          id: 'op-admin',
          username: 'admin',
          fullName: 'Plant Administrator',
          passwordHash: '',
          role: 'admin',
          isActive: true,
          createdAt: 1000,
        ),
        const SupabaseOperator(
          id: 'op-sms2',
          username: 'sms2',
          fullName: 'SMS 2 Division',
          passwordHash: '',
          role: 'operator',
          isActive: true,
          createdAt: 1000,
        ),
        const SupabaseOperator(
          id: 'op-sponge',
          username: 'Sponge',
          fullName: 'Sponge Iron Incharge',
          passwordHash: '',
          role: 'operator',
          isActive: true,
          createdAt: 1000,
        ),
        const SupabaseOperator(
          id: 'op-rm',
          username: 'rollingmill',
          fullName: 'Rolling Mill Incharge',
          passwordHash: '',
          role: 'operator',
          isActive: true,
          createdAt: 1000,
        ),
      ];

      // 3. Assignments
      activeAssignments = [
        {'operator_id': 'op-sms2', 'device_id': 'dev-sms2-fur'},
        {'operator_id': 'op-sms2', 'device_id': 'dev-sms2-fan1'},
        {'operator_id': 'op-sponge', 'device_id': 'dev-cooler-dd1'},
        {'operator_id': 'op-sponge', 'device_id': 'dev-sid-process'},
        {'operator_id': 'op-rm', 'device_id': 'dev-rmd-water'},
      ];

      replacements = [];

      // 4. Sample readings for January 2026
      // Initial on 01-Jan-2026
      final d01Ms = AppDateUtils.toLocalMidnightUtcMs(DateTime(2026, 1, 1));
      // Mid on 15-Jan-2026
      final d15Ms = AppDateUtils.toLocalMidnightUtcMs(DateTime(2026, 1, 15));
      // Final on 01-Feb-2026
      final dFeb01Ms = AppDateUtils.toLocalMidnightUtcMs(DateTime(2026, 2, 1));

      readings = [
        // 132kv
        SupabaseReadingWithDetails(
          reading: SupabaseReading(
            id: 'r-132-01',
            operatorId: 'op-admin',
            deviceId: 'dev-132kv',
            readingDate: d01Ms,
            readingType: 'day',
            heatNumber: '',
            readingValues: jsonEncode({'KWH': 50000.0, 'KWHLT': 25000.0, 'KVAH': 52000.0, 'PF': 0.96}),
            createdAt: d01Ms + 3600000,
          ),
          operatorName: 'Plant Administrator',
          deviceName: '132kv',
          deviceMatrix: 'KWH,KWHLT,KVAH,PF',
          deviceDayMatrix: 'KWH,KWHLT,KVAH,PF',
          deviceRequiresHeatDay: false,
          deviceHeatUnitFactors: '{}',
          deviceDayUnitFactors: '{"KWH": 200000.0}',
        ),
        SupabaseReadingWithDetails(
          reading: SupabaseReading(
            id: 'r-132-feb01',
            operatorId: 'op-admin',
            deviceId: 'dev-132kv',
            readingDate: dFeb01Ms,
            readingType: 'day',
            heatNumber: '',
            readingValues: jsonEncode({'KWH': 50050.0, 'KWHLT': 25025.0, 'KVAH': 52055.0, 'PF': 0.95}),
            createdAt: dFeb01Ms + 3600000,
          ),
          operatorName: 'Plant Administrator',
          deviceName: '132kv',
          deviceMatrix: 'KWH,KWHLT,KVAH,PF',
          deviceDayMatrix: 'KWH,KWHLT,KVAH,PF',
          deviceRequiresHeatDay: false,
          deviceHeatUnitFactors: '{}',
          deviceDayUnitFactors: '{"KWH": 200000.0}',
        ),
        // SMS 2 Furnace Day
        SupabaseReadingWithDetails(
          reading: SupabaseReading(
            id: 'r-sms2-01',
            operatorId: 'op-sms2',
            deviceId: 'dev-sms2-fur',
            readingDate: d01Ms,
            readingType: 'day',
            heatNumber: '',
            readingValues: jsonEncode({'KWH': 1000.0, 'KWHLT': 500.0, 'KVAH': 1050.0, 'PF': 0.98}),
            createdAt: d01Ms + 4000000,
          ),
          operatorName: 'SMS 2 Division',
          deviceName: 'SMS2',
          deviceMatrix: 'KWH,KWHLT',
          deviceDayMatrix: 'KWH,KWHLT,KVAH,PF',
          deviceRequiresHeatDay: true,
          deviceHeatUnitFactors: '{"KWH": 80.0}',
          deviceDayUnitFactors: '{"KWH": 80.0}',
        ),
        SupabaseReadingWithDetails(
          reading: SupabaseReading(
            id: 'r-sms2-feb01',
            operatorId: 'op-sms2',
            deviceId: 'dev-sms2-fur',
            readingDate: dFeb01Ms,
            readingType: 'day',
            heatNumber: '',
            readingValues: jsonEncode({'KWH': 1500.0, 'KWHLT': 750.0, 'KVAH': 1570.0, 'PF': 0.97}),
            createdAt: dFeb01Ms + 4000000,
          ),
          operatorName: 'SMS 2 Division',
          deviceName: 'SMS2',
          deviceMatrix: 'KWH,KWHLT',
          deviceDayMatrix: 'KWH,KWHLT,KVAH,PF',
          deviceRequiresHeatDay: true,
          deviceHeatUnitFactors: '{"KWH": 80.0}',
          deviceDayUnitFactors: '{"KWH": 80.0}',
        ),
        // Dedusting
        SupabaseReadingWithDetails(
          reading: SupabaseReading(
            id: 'r-dd-01',
            operatorId: 'op-sponge',
            deviceId: 'dev-cooler-dd1',
            readingDate: d01Ms,
            readingType: 'day',
            heatNumber: '',
            readingValues: jsonEncode({'KWH': 120.0}),
            createdAt: d01Ms + 5000000,
          ),
          operatorName: 'Sponge Iron Incharge',
          deviceName: 'COOLER DD 1',
          deviceMatrix: 'KWH',
          deviceDayMatrix: 'KWH',
          deviceRequiresHeatDay: false,
          deviceHeatUnitFactors: '{}',
          deviceDayUnitFactors: '{}',
          deviceCategory: DeviceCategory.dedusting,
        ),
        // Water
        SupabaseReadingWithDetails(
          reading: SupabaseReading(
            id: 'r-water-01',
            operatorId: 'op-sponge',
            deviceId: 'dev-sid-process',
            readingDate: d01Ms,
            readingType: 'day',
            heatNumber: '',
            readingValues: jsonEncode({'LTRS': 800.0}),
            createdAt: d01Ms + 6000000,
          ),
          operatorName: 'Sponge Iron Incharge',
          deviceName: 'SID PROCESS',
          deviceMatrix: 'LTRS',
          deviceDayMatrix: 'LTRS',
          deviceRequiresHeatDay: false,
          deviceHeatUnitFactors: '{}',
          deviceDayUnitFactors: '{}',
          deviceCategory: DeviceCategory.water,
        ),
      ];
    });

    test('generates all 4 requested sheets with correct names and date rows', () async {
      final usecase = ExportReadingsUseCase();
      final filePath = await usecase.exportMonthlyReportToExcel(
        year: 2026,
        month: 1, // January 2026
        devices: devices,
        operators: operators,
        activeAssignments: activeAssignments,
        readings: readings,
        replacements: replacements,
      );

      expect(filePath, isNotNull);
      final file = File(filePath!);
      expect(await file.exists(), isTrue);

      // Read back Excel file to verify contents
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      // Verify the 4 exact sheets exist
      expect(excel.tables.containsKey('Energy_Abstract'), isTrue);
      expect(excel.tables.containsKey('SMS_Divisions'), isTrue);
      expect(excel.tables.containsKey('SID_Dedusting'), isTrue);
      expect(excel.tables.containsKey('Water_Meters'), isTrue);
      expect(excel.tables.containsKey('Sheet1'), isFalse);

      // Verify Energy_Abstract sheet
      final energySheet = excel.tables['Energy_Abstract']!;
      expect(energySheet.maxRows, greaterThan(32)); // 31 days + 1st next month + headers + summary

      // Verify SMS_Divisions sheet
      final smsSheet = excel.tables['SMS_Divisions']!;
      expect(smsSheet.maxRows, greaterThan(32));

      // Verify SID_Dedusting sheet
      final dedustingSheet = excel.tables['SID_Dedusting']!;
      expect(dedustingSheet.maxRows, greaterThan(32));

      // Verify Water_Meters sheet
      final waterSheet = excel.tables['Water_Meters']!;
      expect(waterSheet.maxRows, greaterThan(32));

      // Clean up test file
      try {
        await file.delete();
      } catch (_) {}
    });
  });
}
