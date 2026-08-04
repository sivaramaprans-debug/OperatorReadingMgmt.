import 'dart:convert';
import '../database/repositories/supabase_audit_repository.dart';

/// Convenience wrapper around SupabaseAuditRepository.
/// Action naming convention: '<entity>.<verb>'
/// Examples: 'reading.create', 'operator.deactivate', 'password.reset'
class AuditService {
  AuditService.fromSupabase(this._repo);

  final SupabaseAuditRepository _repo;

  Future<void> log({
    required String actorId,
    required String actorRole,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _repo.insert(
        actorId: actorId,
        action: action,
        entityType: entityType,
        entityId: entityId,
        details: metadata != null ? jsonEncode(metadata) : null,
      );
    } catch (_) {
      // Audit failures must never break the main flow
    }
  }

  Future<void> adminLog({
    required String adminId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? metadata,
  }) =>
      log(
        actorId: adminId,
        actorRole: 'admin',
        action: action,
        entityType: entityType,
        entityId: entityId,
        metadata: metadata,
      );

  Future<void> operatorLog({
    required String operatorId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? metadata,
  }) =>
      log(
        actorId: operatorId,
        actorRole: 'operator',
        action: action,
        entityType: entityType,
        entityId: entityId,
        metadata: metadata,
      );
}
