import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../domain/usecases/admin_dashboard_usecase.dart';

final adminDashboardUseCaseProvider = Provider((ref) => AdminDashboardUseCase(
  operatorsRepo: ref.watch(supabaseOperatorsRepoProvider),
  devicesRepo: ref.watch(supabaseDevicesRepoProvider),
  readingsRepo: ref.watch(supabaseReadingsRepoProvider),
));

final adminDashboardStatsProvider = FutureProvider.autoDispose<AdminDashboardStats>((ref) {
  return ref.watch(adminDashboardUseCaseProvider).call();
});
