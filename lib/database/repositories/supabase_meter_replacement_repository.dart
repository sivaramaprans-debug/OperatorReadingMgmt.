import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../supabase_client.dart';
import '../../core/utils/app_date_utils.dart';

/// Plain Dart model for a meter replacement event.
class SupabaseMeterReplacement {
  const SupabaseMeterReplacement({
    required this.id,
    required this.deviceId,
    required this.replacementDate,
    required this.businessDayMs,
    required this.oldMeterFinalValues,
    required this.oldMeterFactors,
    required this.newMeterInitialValues,
    required this.newMeterFactors,
    this.notes = '',
    required this.createdAt,
  });

  final String id;
  final String deviceId;
  final int replacementDate;    // Exact timestamp of physical changeover in ms
  final int businessDayMs;      // Midnight UTC ms of the transition business day
  final String oldMeterFinalValues;   // JSON string e.g. {"KWH": 998999.0, ...}
  final String oldMeterFactors;       // JSON string e.g. {"KWH": 80.0, ...}
  final String newMeterInitialValues; // JSON string e.g. {"KWH": 0.0, ...}
  final String newMeterFactors;       // JSON string e.g. {"KWH": 160.0, ...}
  final String notes;
  final int createdAt;

  Map<String, double> get parsedOldFinalValues => _parseMap(oldMeterFinalValues);
  Map<String, double> get parsedOldFactors => _parseMap(oldMeterFactors);
  Map<String, double> get parsedNewInitialValues => _parseMap(newMeterInitialValues);
  Map<String, double> get parsedNewFactors => _parseMap(newMeterFactors);

  static Map<String, double> _parseMap(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  factory SupabaseMeterReplacement.fromMap(Map<String, dynamic> m) => SupabaseMeterReplacement(
        id: m['id'] as String,
        deviceId: m['device_id'] as String,
        replacementDate: m['replacement_date'] as int,
        businessDayMs: m['business_day_ms'] as int? ?? AppDateUtils.toBusinessDayMidnightUtcMs(m['replacement_date'] as int),
        oldMeterFinalValues: m['old_meter_final_values'] as String? ?? '{}',
        oldMeterFactors: m['old_meter_factors'] as String? ?? '{}',
        newMeterInitialValues: m['new_meter_initial_values'] as String? ?? '{}',
        newMeterFactors: m['new_meter_factors'] as String? ?? '{}',
        notes: m['notes'] as String? ?? '',
        createdAt: m['created_at'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'device_id': deviceId,
        'replacement_date': replacementDate,
        'business_day_ms': businessDayMs,
        'old_meter_final_values': oldMeterFinalValues,
        'old_meter_factors': oldMeterFactors,
        'new_meter_initial_values': newMeterInitialValues,
        'new_meter_factors': newMeterFactors,
        'notes': notes,
        'created_at': createdAt,
      };
}

class SupabaseMeterReplacementRepository {
  static const _table = 'device_meter_replacements';
  final _uuid = const Uuid();

  Future<List<SupabaseMeterReplacement>> getAll() async {
    try {
      final data = await supabase.from(_table).select().order('replacement_date', ascending: false);
      return (data as List).map((m) => SupabaseMeterReplacement.fromMap(m as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<SupabaseMeterReplacement>> getForDevice(String deviceId) async {
    try {
      final data = await supabase
          .from(_table)
          .select()
          .eq('device_id', deviceId)
          .order('replacement_date', ascending: false);
      return (data as List).map((m) => SupabaseMeterReplacement.fromMap(m as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> recordReplacement({
    required String deviceId,
    required int replacementDate,
    required Map<String, double> oldFinalValues,
    required Map<String, double> oldFactors,
    required Map<String, double> newInitialValues,
    required Map<String, double> newFactors,
    String notes = '',
  }) async {
    final id = _uuid.v4();
    final now = AppDateUtils.nowUtcMs();
    final bizDay = AppDateUtils.toBusinessDayMidnightUtcMs(replacementDate);

    await supabase.from(_table).insert({
      'id': id,
      'device_id': deviceId,
      'replacement_date': replacementDate,
      'business_day_ms': bizDay,
      'old_meter_final_values': jsonEncode(oldFinalValues),
      'old_meter_factors': jsonEncode(oldFactors),
      'new_meter_initial_values': jsonEncode(newInitialValues),
      'new_meter_factors': jsonEncode(newFactors),
      'notes': notes,
      'created_at': now,
    });
  }

  Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }
}
