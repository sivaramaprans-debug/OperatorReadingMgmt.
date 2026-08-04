import 'package:uuid/uuid.dart';
import '../supabase_client.dart';
import '../../core/utils/app_date_utils.dart';

/// Plain Dart model for an operator (replaces Drift-generated Operator).
class SupabaseOperator {
  const SupabaseOperator({
    required this.id,
    required this.username,
    required this.fullName,
    required this.passwordHash,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String username;
  final String fullName;
  final String passwordHash;
  final String role; // 'admin' | 'operator'
  final bool isActive;
  final int createdAt;

  factory SupabaseOperator.fromMap(Map<String, dynamic> m) => SupabaseOperator(
        id: m['id'] as String,
        username: m['username'] as String,
        fullName: m['full_name'] as String,
        passwordHash: m['password_hash'] as String,
        role: m['role'] as String? ?? 'operator',
        isActive: m['is_active'] as bool? ?? true,
        createdAt: m['created_at'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'password_hash': passwordHash,
        'role': role,
        'is_active': isActive,
        'created_at': createdAt,
      };
}

class SupabaseOperatorsRepository {
  static const _table = 'operators';
  final _uuid = const Uuid();

  Future<List<SupabaseOperator>> getAll() async {
    final data = await supabase.from(_table).select();
    return (data as List).map((m) => SupabaseOperator.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<List<SupabaseOperator>> getActive() async {
    final data = await supabase.from(_table).select().eq('is_active', true).eq('role', 'operator');
    return (data as List).map((m) => SupabaseOperator.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<SupabaseOperator?> findByUsername(String username) async {
    final data = await supabase.from(_table).select().eq('username', username).maybeSingle();
    if (data == null) return null;
    return SupabaseOperator.fromMap(data);
  }

  Future<SupabaseOperator?> findById(String id) async {
    final data = await supabase.from(_table).select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return SupabaseOperator.fromMap(data);
  }

  Future<void> create({
    required String username,
    required String fullName,
    required String passwordHash,
    required String role,
  }) async {
    final now = AppDateUtils.nowUtcMs();
    await supabase.from(_table).insert({
      'id': _uuid.v4(),
      'username': username,
      'full_name': fullName,
      'password_hash': passwordHash,
      'role': role,
      'is_active': true,
      'created_at': now,
    });
  }

  Future<void> updatePasswordHash(String id, String newHash) async {
    await supabase.from(_table).update({'password_hash': newHash}).eq('id', id);
  }

  Future<void> setActive(String id, {required bool active}) async {
    await supabase.from(_table).update({'is_active': active}).eq('id', id);
  }

  Future<void> update(String id, {String? fullName, String? username}) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (username != null) updates['username'] = username;
    if (updates.isNotEmpty) {
      await supabase.from(_table).update(updates).eq('id', id);
    }
  }

  Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }

  /// Seed default admin if none exists.
  Future<bool> hasAdminRole() async {
    final data = await supabase.from(_table).select('id').eq('role', 'admin').limit(1);
    return (data as List).isNotEmpty;
  }

  Future<void> seedDefaultAdmin(String username, String passwordHash) async {
    final exists = await hasAdminRole();
    if (exists) return;
    final now = AppDateUtils.nowUtcMs();
    await supabase.from(_table).insert({
      'id': _uuid.v4(),
      'username': username,
      'full_name': 'Administrator',
      'password_hash': passwordHash,
      'role': 'admin',
      'is_active': true,
      'created_at': now,
    });
  }
}
