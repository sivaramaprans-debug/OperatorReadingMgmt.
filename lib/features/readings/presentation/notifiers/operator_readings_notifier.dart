import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';

/// Live readings for a specific device for the logged-in operator.
final operatorReadingsForDeviceProvider =
    FutureProvider.autoDispose.family<List<SupabaseReading>, String>(
        (ref, deviceId) async {
  final user = ref.watch(authNotifierProvider.notifier).currentUser;
  if (user == null) return [];
  final repo = ref.watch(supabaseReadingsRepoProvider);
  final all = await repo.getForOperator(user.id);
  return all.where((r) => r.deviceId == deviceId).toList();
});

/// Devices assigned to the current operator.
final assignedActiveDevicesProvider =
    FutureProvider.autoDispose<List<SupabaseDevice>>((ref) async {
  final user = ref.watch(authNotifierProvider.notifier).currentUser;
  if (user == null) return [];
  return ref
      .watch(supabaseDevicesRepoProvider)
      .getAssignedToOperator(user.id);
});
