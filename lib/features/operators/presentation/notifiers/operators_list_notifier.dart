import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';

/// All operators list (FutureProvider backed by Supabase).
final operatorsListProvider =
    FutureProvider.autoDispose<List<SupabaseOperator>>((ref) {
  return ref.watch(supabaseOperatorsRepoProvider).getAll();
});

class OperatorsListNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> toggleStatus(String operatorId, bool isActive) async {
    state = const AsyncLoading();
    final admin = ref.read(authNotifierProvider.notifier).currentUser;
    if (admin == null || !admin.isAdmin) {
      state = AsyncError('Unauthorized', StackTrace.current);
      return false;
    }

    try {
      await ref
          .read(supabaseOperatorsRepoProvider)
          .setActive(operatorId, active: isActive);
      state = const AsyncData(null);
      ref.invalidate(operatorsListProvider);
      return true;
    } catch (e) {
      state = AsyncError('Failed: $e', StackTrace.current);
      return false;
    }
  }
}

final operatorsListNotifierProvider =
    NotifierProvider<OperatorsListNotifier, AsyncValue<void>>(
        OperatorsListNotifier.new);
