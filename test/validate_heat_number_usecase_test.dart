import 'package:flutter_test/flutter_test.dart';
import 'package:operator_reading_mgmt/database/repositories/supabase_readings_repository.dart';
import 'package:operator_reading_mgmt/features/readings/domain/usecases/validate_heat_number_usecase.dart';

class FakeReadingsRepo extends SupabaseReadingsRepository {
  FakeReadingsRepo({
    this.lastHeatReading,
    this.lastNumberedHeatReading,
  });

  SupabaseReading? lastHeatReading;
  SupabaseReading? lastNumberedHeatReading;

  @override
  Future<SupabaseReading?> getLastHeatReading({required String deviceId}) async {
    return lastHeatReading;
  }

  @override
  Future<SupabaseReading?> getLastNumberedHeatReading({required String deviceId}) async {
    return lastNumberedHeatReading;
  }
}

SupabaseReading _createReading({
  required String id,
  required String heatNumber,
  required int createdAt,
}) {
  return SupabaseReading(
    id: id,
    operatorId: 'op-1',
    deviceId: 'dev-1',
    readingDate: createdAt,
    readingType: 'heat',
    heatNumber: heatNumber,
    readingValues: '{KWH: 1000}',
    createdAt: createdAt,
  );
}

void main() {
  group('ValidateHeatNumberUseCase - R/F & Sequential Rules', () {
    test('allows Heat #1 when no previous readings exist', () async {
      final repo = FakeReadingsRepo();
      final usecase = ValidateHeatNumberUseCase(repo);

      final result1 = await usecase(deviceId: 'dev-1', heatNumberText: '1');
      expect(result1.isValid, isTrue);

      final result2 = await usecase(deviceId: 'dev-1', heatNumberText: '2');
      expect(result2.isValid, isFalse);
      expect(result2.error, contains('first heat number must be 1'));
    });

    test('accepts consecutive heat number after Heat 6', () async {
      final heat6 = _createReading(id: 'r6', heatNumber: '6', createdAt: 1000000);
      final repo = FakeReadingsRepo(
        lastHeatReading: heat6,
        lastNumberedHeatReading: heat6,
      );
      final usecase = ValidateHeatNumberUseCase(repo);

      final res7 = await usecase(deviceId: 'dev-1', heatNumberText: '7');
      expect(res7.isValid, isTrue);

      final res6 = await usecase(deviceId: 'dev-1', heatNumberText: '6');
      expect(res6.isValid, isFalse);
      expect(res6.error, contains('already the last recorded heat'));

      final res8 = await usecase(deviceId: 'dev-1', heatNumberText: '8');
      expect(res8.isValid, isFalse);
      expect(res8.error, contains('must enter Heat #7'));
    });

    test('allows starting new cycle with Heat 1 after Heat 6', () async {
      final heat6 = _createReading(id: 'r6', heatNumber: '6', createdAt: 1000000);
      final repo = FakeReadingsRepo(
        lastHeatReading: heat6,
        lastNumberedHeatReading: heat6,
      );
      final usecase = ValidateHeatNumberUseCase(repo);

      final res1 = await usecase(deviceId: 'dev-1', heatNumberText: '1');
      expect(res1.isValid, isTrue);
    });

    test('rejects entering Heat 1 immediately (< 6 hrs) after Heat 1', () async {
      // Heat 1 recorded 1 hour ago
      final oneHourAgo = DateTime.now().toUtc().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final heat1 = _createReading(id: 'r1', heatNumber: '1', createdAt: oneHourAgo);
      final repo = FakeReadingsRepo(
        lastHeatReading: heat1,
        lastNumberedHeatReading: heat1,
      );
      final usecase = ValidateHeatNumberUseCase(repo);

      final res1 = await usecase(deviceId: 'dev-1', heatNumberText: '1');
      expect(res1.isValid, isFalse);
      expect(res1.error, contains('minimum 6-hour gap'));
    });

    test('allows entering Heat 1 after Heat 1 when >= 6 hrs have passed (crucible switchover)', () async {
      // Heat 1 recorded 7 hours ago
      final sevenHoursAgo = DateTime.now().toUtc().subtract(const Duration(hours: 7)).millisecondsSinceEpoch;
      final heat1 = _createReading(id: 'r1', heatNumber: '1', createdAt: sevenHoursAgo);
      final repo = FakeReadingsRepo(
        lastHeatReading: heat1,
        lastNumberedHeatReading: heat1,
      );
      final usecase = ValidateHeatNumberUseCase(repo);

      final res1 = await usecase(deviceId: 'dev-1', heatNumberText: '1');
      expect(res1.isValid, isTrue);
    });

    test('accepts R/F and rf at any time in heat sequence', () async {
      final heat6 = _createReading(id: 'r6', heatNumber: '6', createdAt: 1000000);
      final repo = FakeReadingsRepo(
        lastHeatReading: heat6,
        lastNumberedHeatReading: heat6,
      );
      final usecase = ValidateHeatNumberUseCase(repo);

      final resRF = await usecase(deviceId: 'dev-1', heatNumberText: 'R/F');
      expect(resRF.isValid, isTrue);
      expect(resRF.expectedNext, 7);

      final resRfLower = await usecase(deviceId: 'dev-1', heatNumberText: 'rf');
      expect(resRfLower.isValid, isTrue);
      expect(resRfLower.expectedNext, 7);
    });

    test('after R/F following Heat 6, next expected heat continues as Heat 7', () async {
      final heat6 = _createReading(id: 'r6', heatNumber: '6', createdAt: 1000000);
      final rfReading = _createReading(id: 'rf-1', heatNumber: 'R/F', createdAt: 1050000);
      final repo = FakeReadingsRepo(
        lastHeatReading: rfReading,
        lastNumberedHeatReading: heat6,
      );
      final usecase = ValidateHeatNumberUseCase(repo);

      final emptyRes = await usecase(deviceId: 'dev-1', heatNumberText: '');
      expect(emptyRes.expectedNext, 7);

      final res7 = await usecase(deviceId: 'dev-1', heatNumberText: '7');
      expect(res7.isValid, isTrue);

      final resAnotherRF = await usecase(deviceId: 'dev-1', heatNumberText: 'R/F');
      expect(resAnotherRF.isValid, isTrue);

      final res8 = await usecase(deviceId: 'dev-1', heatNumberText: '8');
      expect(res8.isValid, isFalse);
      expect(res8.expectedNext, 7);
    });
  });
}
