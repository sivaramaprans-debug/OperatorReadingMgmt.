import 'package:uuid/uuid.dart';
import '../supabase_client.dart';
import '../../core/utils/app_date_utils.dart';

class SupabaseAuditLog {
  const SupabaseAuditLog({
    required this.id,
    required this.actorId,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.details,
    required this.createdAt,
  });

  final String id;
  final String actorId;
  final String action;
  final String entityType;
  final String entityId;
  final String? details;
  final int createdAt;

  String? get metadataJson => details;
  String get actorRole => 'System';

  factory SupabaseAuditLog.fromMap(Map<String, dynamic> m) => SupabaseAuditLog(
        id: m['id'] as String,
        actorId: m['actor_id'] as String,
        action: m['action'] as String,
        entityType: m['entity_type'] as String,
        entityId: m['entity_id'] as String,
        details: m['details'] as String?,
        createdAt: m['created_at'] as int? ?? 0,
      );
}

class SupabaseAuditRepository {
  static const _table = 'audit_logs';
  final _uuid = const Uuid();

  Future<void> insert({
    required String actorId,
    required String action,
    required String entityType,
    required String entityId,
    String? details,
  }) async {
    await supabase.from(_table).insert({
      'id': _uuid.v4(),
      'actor_id': actorId,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'details': details,
      'created_at': AppDateUtils.nowUtcMs(),
    });
  }

  Future<List<SupabaseAuditLog>> getLatest(int n) async {
    final data = await supabase
        .from(_table)
        .select()
        .order('created_at', ascending: false)
        .limit(n);
    return (data as List).map((m) => SupabaseAuditLog.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<List<SupabaseAuditLog>> getAll({int limit = 50}) async {
    final data = await supabase
        .from(_table)
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((m) => SupabaseAuditLog.fromMap(m as Map<String, dynamic>)).toList();
  }
}
