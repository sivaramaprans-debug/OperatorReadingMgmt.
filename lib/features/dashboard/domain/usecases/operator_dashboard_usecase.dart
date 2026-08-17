import '../../../../core/utils/app_date_utils.dart';
import '../../../../database/supabase_providers.dart';

class OperatorDashboardStats {
  const OperatorDashboardStats({
    required this.assignedDevices,
    required this.todayReadings,
  });
  final int assignedDevices;
  final int todayReadings;
}

class OperatorDashboardUseCase {
  const OperatorDashboardUseCase({
    required this.devicesRepo,
    required this.readingsRepo,
  });
  
  final dynamic devicesRepo;
  final dynamic readingsRepo;

  Future<OperatorDashboardStats> call(String operatorId) async {
    final devices = await devicesRepo.getAssignedToOperator(operatorId);
    final assignedDevices = devices.length;

    final businessDayStart = AppDateUtils.startOfCurrentBusinessDayUtcMs();
    final todayReadings = await readingsRepo.countOperatorTodayReadings(operatorId, businessDayStart);

    return OperatorDashboardStats(
      assignedDevices: assignedDevices,
      todayReadings: todayReadings,
    );
  }
}
