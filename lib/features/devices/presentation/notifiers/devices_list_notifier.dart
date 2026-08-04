import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';

/// Stream-like provider for devices list (now a FutureProvider backed by Supabase).
final devicesListProvider = FutureProvider.autoDispose<List<SupabaseDevice>>((ref) {
  return ref.watch(supabaseDevicesRepoProvider).getAll();
});

class DevicesListNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> toggleStatus(String deviceId, bool isActive) async {
    state = const AsyncLoading();
    final admin = ref.read(authNotifierProvider.notifier).currentUser;
    if (admin == null || !admin.isAdmin) {
      state = AsyncError('Unauthorized', StackTrace.current);
      return false;
    }

    try {
      await ref
          .read(supabaseDevicesRepoProvider)
          .setActive(deviceId, active: isActive);
      state = const AsyncData(null);
      ref.invalidate(devicesListProvider);
      return true;
    } catch (e) {
      state = AsyncError('Toggle failed: $e', StackTrace.current);
      return false;
    }
  }
}

final devicesListNotifierProvider =
    NotifierProvider<DevicesListNotifier, AsyncValue<void>>(DevicesListNotifier.new);
