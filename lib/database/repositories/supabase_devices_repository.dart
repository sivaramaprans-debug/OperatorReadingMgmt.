import 'package:uuid/uuid.dart';
import '../supabase_client.dart';
import '../../core/utils/app_date_utils.dart';

/// Plain Dart model for a device.
class SupabaseDevice {
  const SupabaseDevice({
    required this.id,
    required this.name,
    required this.multiplicationFactor,
    required this.matrix,
    required this.dayMatrix,
    required this.requiresHeatDay,
    required this.heatUnitFactors,
    required this.dayUnitFactors,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final double multiplicationFactor;
  final String matrix;
  final String dayMatrix;
  final bool requiresHeatDay;
  final String heatUnitFactors; // JSON string
  final String dayUnitFactors;  // JSON string
  final bool isActive;
  final int createdAt;

  factory SupabaseDevice.fromMap(Map<String, dynamic> m) => SupabaseDevice(
        id: m['id'] as String,
        name: m['name'] as String,
        multiplicationFactor: (m['multiplication_factor'] as num?)?.toDouble() ?? 1.0,
        matrix: m['matrix'] as String? ?? '',
        dayMatrix: m['day_matrix'] as String? ?? '',
        requiresHeatDay: m['requires_heat_day'] as bool? ?? false,
        heatUnitFactors: m['heat_unit_factors'] as String? ?? '{}',
        dayUnitFactors: m['day_unit_factors'] as String? ?? '{}',
        isActive: m['is_active'] as bool? ?? true,
        createdAt: m['created_at'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'multiplication_factor': multiplicationFactor,
        'matrix': matrix,
        'day_matrix': dayMatrix,
        'requires_heat_day': requiresHeatDay,
        'heat_unit_factors': heatUnitFactors,
        'day_unit_factors': dayUnitFactors,
        'is_active': isActive,
        'created_at': createdAt,
      };
}

class SupabaseDevicesRepository {
  static const _table = 'devices';
  static const _assignmentsTable = 'device_assignments';
  final _uuid = const Uuid();

  Future<List<SupabaseDevice>> getAll() async {
    final data = await supabase.from(_table).select().order('name');
    return (data as List).map((m) => SupabaseDevice.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<List<SupabaseDevice>> getActive() async {
    final data = await supabase.from(_table).select().eq('is_active', true).order('name');
    return (data as List).map((m) => SupabaseDevice.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<SupabaseDevice?> findById(String id) async {
    final data = await supabase.from(_table).select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return SupabaseDevice.fromMap(data);
  }

  /// Devices assigned to a specific operator (active assignments only).
  Future<List<SupabaseDevice>> getAssignedToOperator(String operatorId) async {
    final assignments = await supabase
        .from(_assignmentsTable)
        .select('device_id')
        .eq('operator_id', operatorId)
        .eq('is_active', true);
    final ids = (assignments as List).map((a) => a['device_id'] as String).toList();
    if (ids.isEmpty) return [];
    final data = await supabase.from(_table).select().inFilter('id', ids).eq('is_active', true);
    return (data as List).map((m) => SupabaseDevice.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<String> create({
    required String name,
    required double multiplicationFactor,
    required String matrix,
    required String dayMatrix,
    required bool requiresHeatDay,
    required String heatUnitFactors,
    required String dayUnitFactors,
  }) async {
    final id = _uuid.v4();
    final now = AppDateUtils.nowUtcMs();
    await supabase.from(_table).insert({
      'id': id,
      'name': name,
      'multiplication_factor': multiplicationFactor,
      'matrix': matrix,
      'day_matrix': dayMatrix,
      'requires_heat_day': requiresHeatDay,
      'heat_unit_factors': heatUnitFactors,
      'day_unit_factors': dayUnitFactors,
      'is_active': true,
      'created_at': now,
    });
    return id;
  }

  Future<void> update(String id, {
    String? name,
    double? multiplicationFactor,
    String? matrix,
    String? dayMatrix,
    bool? requiresHeatDay,
    String? heatUnitFactors,
    String? dayUnitFactors,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (multiplicationFactor != null) updates['multiplication_factor'] = multiplicationFactor;
    if (matrix != null) updates['matrix'] = matrix;
    if (dayMatrix != null) updates['day_matrix'] = dayMatrix;
    if (requiresHeatDay != null) updates['requires_heat_day'] = requiresHeatDay;
    if (heatUnitFactors != null) updates['heat_unit_factors'] = heatUnitFactors;
    if (dayUnitFactors != null) updates['day_unit_factors'] = dayUnitFactors;
    if (updates.isNotEmpty) {
      await supabase.from(_table).update(updates).eq('id', id);
    }
  }

  Future<void> setActive(String id, {required bool active}) async {
    await supabase.from(_table).update({'is_active': active}).eq('id', id);
  }

  // Assignment management
  Future<List<String>> getAssignedOperatorIds(String deviceId) async {
    final data = await supabase
        .from(_assignmentsTable)
        .select('operator_id')
        .eq('device_id', deviceId)
        .eq('is_active', true);
    return (data as List).map((a) => a['operator_id'] as String).toList();
  }

  Future<void> assignOperator(String deviceId, String operatorId) async {
    // Check if already assigned
    final existing = await supabase
        .from(_assignmentsTable)
        .select('id')
        .eq('device_id', deviceId)
        .eq('operator_id', operatorId)
        .maybeSingle();
    if (existing != null) {
      await supabase
          .from(_assignmentsTable)
          .update({'is_active': true})
          .eq('device_id', deviceId)
          .eq('operator_id', operatorId);
    } else {
      await supabase.from(_assignmentsTable).insert({
        'id': _uuid.v4(),
        'device_id': deviceId,
        'operator_id': operatorId,
        'assigned_at': AppDateUtils.nowUtcMs(),
        'is_active': true,
      });
    }
  }

  Future<void> unassignOperator(String deviceId, String operatorId) async {
    await supabase
        .from(_assignmentsTable)
        .update({'is_active': false})
        .eq('device_id', deviceId)
        .eq('operator_id', operatorId);
  }

  Future<void> setAssignments(String deviceId, List<String> operatorIds) async {
    // Deactivate all current
    await supabase
        .from(_assignmentsTable)
        .update({'is_active': false})
        .eq('device_id', deviceId);
    // Activate/create for new list
    for (final opId in operatorIds) {
      await assignOperator(deviceId, opId);
    }
  }
}
