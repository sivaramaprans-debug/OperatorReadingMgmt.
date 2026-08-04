import '../../../../core/utils/app_date_utils.dart';
import '../../../../database/supabase_providers.dart';

class AdminDashboardStats {
  const AdminDashboardStats({
    required this.totalOperators,
    required this.activeDevices,
    required this.todayReadings,
  });
  final int totalOperators;
  final int activeDevices;
  final int todayReadings;
}

class AdminDashboardUseCase {
  const AdminDashboardUseCase({
    required this.operatorsRepo,
    required this.devicesRepo,
    required this.readingsRepo,
  });
  
  final dynamic operatorsRepo;
  final dynamic devicesRepo;
  final dynamic readingsRepo;

  Future<AdminDashboardStats> call() async {
    final operators = await operatorsRepo.getAll();
    final totalOperators = operators.length;

    final devices = await devicesRepo.getAll();
    final activeDevices = devices.length;

    final todayMidnight = AppDateUtils.todayLocalMidnightUtcMs();
    final todayReadings = await readingsRepo.countTodayReadings(todayMidnight);

    return AdminDashboardStats(
      totalOperators: totalOperators,
      activeDevices: activeDevices,
      todayReadings: todayReadings,
    );
  }
}
