import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_audit_repository.dart';
import '../../domain/usecases/get_audit_logs_usecase.dart';

final getAuditLogsUseCaseProvider = Provider((ref) => GetAuditLogsUseCase(ref.watch(supabaseAuditRepoProvider)));

final auditLogsProvider = FutureProvider.autoDispose<List<SupabaseAuditLog>>((ref) {
  return ref.watch(getAuditLogsUseCaseProvider).call(limit: 100); // 100 recent logs for now
});
