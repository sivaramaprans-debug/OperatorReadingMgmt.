import '../../../../database/repositories/supabase_audit_repository.dart';

class GetAuditLogsUseCase {
  const GetAuditLogsUseCase(this.auditRepo);
  final SupabaseAuditRepository auditRepo;

  Future<List<SupabaseAuditLog>> call({int limit = 50, int offset = 0}) {
    return auditRepo.getAll(limit: limit);
  }
}
