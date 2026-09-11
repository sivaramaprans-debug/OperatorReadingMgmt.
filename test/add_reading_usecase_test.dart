import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_reading_mgmt/database/repositories/supabase_devices_repository.dart';
import 'package:operator_reading_mgmt/database/repositories/supabase_readings_repository.dart';
import 'package:operator_reading_mgmt/features/readings/domain/usecases/add_reading_usecase.dart';

class FakeDevicesRepo extends SupabaseDevicesRepository {
  FakeDevicesRepo(this.device);
  final SupabaseDevice? device;

  @override
  Future<SupabaseDevice?> findById(String id) async => device;
}

class FakeAddReadingsRepo extends SupabaseReadingsRepository {
  FakeAddReadingsRepo({
    this.prevReading,
    this.heatInBizDay = false,
    this.isDuplicate = false,
  });

  SupabaseReading? prevReading;
  bool heatInBizDay;
  bool isDuplicate;
  int insertCallCount = 0;
  Map<String, dynamic>? lastInserted;

  @override
  Future<SupabaseReading?> getPreviousReading({
    required String deviceId,
    required String readingType,
    required int readingDateMs,
    String heatNumber = '',
    String? excludeReadingId,
  }) async {
    return prevReading;
  }

  @override
  Future<bool> existsHeatNumberInBusinessDay({
    required String deviceId,
    required String heatNumber,
    required int readingDateMs,
    String? excludeId,
  }) async {
    return heatInBizDay;
  }

  @override
  Future<bool> existsDuplicate({
    required String deviceId,
    required int readingDateMs,
    required String readingType,
    String heatNumber = '',
    String? excludeId,
  }) async {
    return isDuplicate;
  }

  @override
  Future<String> insert({
    required String operatorId,
    required String deviceId,
    required int readingDate,
    required String readingType,
    required String heatNumber,
    required String readingValues,
  }) async {
    insertCallCount++;
    lastInserted = {
      'operatorId': operatorId,
      'deviceId': deviceId,
      'readingDate': readingDate,
      'readingType': readingType,
      'heatNumber': heatNumber,
      'readingValues': readingValues,
    };
    return 'new-id-123';
  }
}

SupabaseDevice _createDevice() {
  return const SupabaseDevice(
    id: 'sms-furnace-1',
    name: 'SMS Furnace 1',
    multiplicationFactor: 1.0,
    matrix: 'KWH,KVAH',
    dayMatrix: '',
    requiresHeatDay: true,
    heatUnitFactors: '{KWH: 1.0}',
    dayUnitFactors: '{}',
    isActive: true,
    createdAt: 100000,
  );
}

void main() {
  group('AddReadingUseCase - Zero Difference & Duplicates Prevention', () {
    test('rejects reading when cumulative meter values have zero difference from previous', () async {
      final prev = SupabaseReading(
        id: 'prev-1',
        operatorId: 'op-1',
        deviceId: 'sms-furnace-1',
        readingDate: 1000000,
        readingType: 'heat',
        heatNumber: '1',
        readingValues: jsonEncode({'KWH': 250417472.0, 'KVAH': 250418000.0}),
        createdAt: 1000000,
      );

      final devicesRepo = FakeDevicesRepo(_createDevice());
      final readingsRepo = FakeAddReadingsRepo(prevReading: prev);
      final usecase = AddReadingUseCase(devicesRepo: devicesRepo, readingsRepo: readingsRepo);

      // Submitting identical values to previous reading
      final (id, failure) = await usecase(
        operatorId: 'op-1',
        deviceId: 'sms-furnace-1',
        readingType: 'heat',
        heatNumber: '2',
        values: {'KWH': 250417472.0, 'KVAH': 250418000.0},
      );

      expect(id, isNull);
      expect(failure, isNotNull);
      expect(failure!.message, contains('0 difference'));
      expect(readingsRepo.insertCallCount, 0);
    });

    test('rejects heat reading if heat number already exists in current business cycle', () async {
      final devicesRepo = FakeDevicesRepo(_createDevice());
      final readingsRepo = FakeAddReadingsRepo(heatInBizDay: true);
      final usecase = AddReadingUseCase(devicesRepo: devicesRepo, readingsRepo: readingsRepo);

      final (id, failure) = await usecase(
        operatorId: 'op-1',
        deviceId: 'sms-furnace-1',
        readingType: 'heat',
        heatNumber: '7',
        values: {'KWH': 250420000.0, 'KVAH': 250422000.0},
      );

      expect(id, isNull);
      expect(failure, isNotNull);
      expect(failure!.message, contains('already exists in the current business cycle'));
      expect(readingsRepo.insertCallCount, 0);
    });

    test('accepts valid heat reading with advance in meter values and normalizes R/F', () async {
      final prev = SupabaseReading(
        id: 'prev-1',
        operatorId: 'op-1',
        deviceId: 'sms-furnace-1',
        readingDate: 1000000,
        readingType: 'heat',
        heatNumber: '6',
        readingValues: jsonEncode({'KWH': 250417000.0, 'KVAH': 250418000.0}),
        createdAt: 1000000,
      );

      final devicesRepo = FakeDevicesRepo(_createDevice());
      final readingsRepo = FakeAddReadingsRepo(prevReading: prev);
      final usecase = AddReadingUseCase(devicesRepo: devicesRepo, readingsRepo: readingsRepo);

      // Submit R/F reading with meter advance
      final (id, failure) = await usecase(
        operatorId: 'op-1',
        deviceId: 'sms-furnace-1',
        readingType: 'heat',
        heatNumber: 'rf', // should be normalized to R/F
        values: {'KWH': 250417500.0, 'KVAH': 250418500.0},
      );

      expect(failure, isNull);
      expect(id, equals('new-id-123'));
      expect(readingsRepo.insertCallCount, 1);
      expect(readingsRepo.lastInserted?['heatNumber'], equals('R/F'));
    });
  });
}
