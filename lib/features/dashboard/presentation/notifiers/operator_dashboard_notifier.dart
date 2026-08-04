import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../domain/usecases/operator_dashboard_usecase.dart';

final operatorDashboardUseCaseProvider = Provider((ref) => OperatorDashboardUseCase(
  devicesRepo: ref.watch(supabaseDevicesRepoProvider),
  readingsRepo: ref.watch(supabaseReadingsRepoProvider),
));

final operatorDashboardStatsProvider = FutureProvider.autoDispose<OperatorDashboardStats>((ref) {
  final user = ref.watch(authNotifierProvider.notifier).currentUser;
  if (user == null) return Future.value(const OperatorDashboardStats(assignedDevices: 0, todayReadings: 0));
  return ref.watch(operatorDashboardUseCaseProvider).call(user.id);
});
