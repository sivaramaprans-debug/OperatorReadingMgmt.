import 'package:uuid/uuid.dart';
import '../supabase_client.dart';
import '../../core/utils/app_date_utils.dart';

/// Plain Dart model for a reading.
class SupabaseReading {
  const SupabaseReading({
    required this.id,
    required this.operatorId,
    required this.deviceId,
    required this.readingDate,
    required this.readingType,
    required this.heatNumber,
    required this.readingValues,
    required this.createdAt,
  });

  final String id;
  final String operatorId;
  final String deviceId;
  final int readingDate;
  final String readingType;
  final String heatNumber;
  final String readingValues; // JSON
  final int createdAt;

  factory SupabaseReading.fromMap(Map<String, dynamic> m) => SupabaseReading(
        id: m['id'] as String,
        operatorId: m['operator_id'] as String,
        deviceId: m['device_id'] as String,
        readingDate: m['reading_date'] as int,
        readingType: m['reading_type'] as String? ?? 'standard',
        heatNumber: m['heat_number'] as String? ?? '',
        readingValues: m['reading_values'] as String? ?? '{}',
        createdAt: m['created_at'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'operator_id': operatorId,
        'device_id': deviceId,
        'reading_date': readingDate,
        'reading_type': readingType,
        'heat_number': heatNumber,
        'reading_values': readingValues,
        'created_at': createdAt,
      };
}

/// Joined reading with device and operator names.
class SupabaseReadingWithDetails {
  const SupabaseReadingWithDetails({
    required this.reading,
    required this.operatorName,
    required this.deviceName,
    required this.deviceMatrix,
    required this.deviceDayMatrix,
    required this.deviceRequiresHeatDay,
    required this.deviceHeatUnitFactors,
    required this.deviceDayUnitFactors,
    this.deviceCategory = 'energy',
    this.deviceMf = 1.0,
  });

  final SupabaseReading reading;
  final String operatorName;
  final String deviceName;
  final String deviceMatrix;
  final String deviceDayMatrix;
  final bool deviceRequiresHeatDay;
  final String deviceHeatUnitFactors;
  final String deviceDayUnitFactors;
  /// 'energy' | 'dedusting' | 'water'
  final String deviceCategory;
  /// Device-level multiplication factor (used for dedusting/water single-metric calc)
  final double deviceMf;

  bool get isDedusting => deviceCategory == 'dedusting';
  bool get isWater     => deviceCategory == 'water';
  bool get isEnergy    => deviceCategory == 'energy';
}

class SupabaseReadingsRepository {
  static const _table = 'readings';
  final _uuid = const Uuid();

  Future<String> insert({
    required String operatorId,
    required String deviceId,
    required int readingDate,
    required String readingType,
    required String heatNumber,
    required String readingValues,
  }) async {
    final id = _uuid.v4();
    final now = AppDateUtils.nowUtcMs();
    await supabase.from(_table).insert({
      'id': id,
      'operator_id': operatorId,
      'device_id': deviceId,
      'reading_date': readingDate,
      'reading_type': readingType,
      'heat_number': heatNumber,
      'reading_values': readingValues,
      'created_at': now,
    });
    return id;
  }

  Future<void> update(String id, {
    required int readingDate,
    required String readingType,
    required String heatNumber,
    required String readingValues,
  }) async {
    await supabase.from(_table).update({
      'reading_date': readingDate,
      'reading_type': readingType,
      'heat_number': heatNumber,
      'reading_values': readingValues,
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }

  Future<void> deleteByDeviceId(String deviceId) async {
    await supabase.from(_table).delete().eq('device_id', deviceId);
  }

  Future<SupabaseReading?> findById(String id) async {
    final data = await supabase.from(_table).select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return SupabaseReading.fromMap(data);
  }

  Future<List<SupabaseReading>> getForOperator(String operatorId, {int limit = 100}) async {
    final data = await supabase
        .from(_table)
        .select()
        .eq('operator_id', operatorId)
        .order('reading_date', ascending: false)
        .limit(limit);
    return (data as List).map((m) => SupabaseReading.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<List<SupabaseReadingWithDetails>> search({
    String? operatorId,
    List<String>? deviceIds,
    String? readingType,
    int? fromDateMs,
    int? toDateMs,
    int limit = 100,
  }) async {
    // Fetch readings with filter
    var query = supabase.from(_table).select(
      '*, operators(username, full_name), devices(name, matrix, day_matrix, requires_heat_day, heat_unit_factors, day_unit_factors, device_category, multiplication_factor)',
    );

    if (operatorId != null) query = query.eq('operator_id', operatorId) as dynamic;
    if (deviceIds != null && deviceIds.isNotEmpty) query = query.inFilter('device_id', deviceIds) as dynamic;
    if (readingType != null) query = query.eq('reading_type', readingType) as dynamic;
    if (fromDateMs != null) query = query.gte('reading_date', fromDateMs) as dynamic;
    if (toDateMs != null) query = query.lte('reading_date', toDateMs) as dynamic;

    final data = await (query as dynamic).order('reading_date', ascending: false).limit(limit);

    return (data as List).map((m) {
      final map = m as Map<String, dynamic>;
      final opMap = map['operators'] as Map<String, dynamic>? ?? {};
      final devMap = map['devices'] as Map<String, dynamic>? ?? {};
      return SupabaseReadingWithDetails(
        reading: SupabaseReading.fromMap(map),
        operatorName: opMap['full_name'] as String? ?? opMap['username'] as String? ?? '—',
        deviceName: devMap['name'] as String? ?? '—',
        deviceMatrix: devMap['matrix'] as String? ?? '',
        deviceDayMatrix: devMap['day_matrix'] as String? ?? '',
        deviceRequiresHeatDay: devMap['requires_heat_day'] as bool? ?? false,
        deviceHeatUnitFactors: devMap['heat_unit_factors'] as String? ?? '{}',
        deviceDayUnitFactors: devMap['day_unit_factors'] as String? ?? '{}',
        deviceCategory: devMap['device_category'] as String? ?? 'energy',
        deviceMf: (devMap['multiplication_factor'] as num?)?.toDouble() ?? 1.0,
      );
    }).toList();
  }

  Future<bool> existsDuplicate({
    required String deviceId,
    required int readingDateMs,
    required String readingType,
    required String heatNumber,
    String? excludeId,
  }) async {
    var query = supabase
        .from(_table)
        .select('id')
        .eq('device_id', deviceId)
        .eq('reading_date', readingDateMs)
        .eq('reading_type', readingType)
        .eq('heat_number', heatNumber);
    if (excludeId != null) query = query.neq('id', excludeId);
    final data = await query.limit(1);
    return (data as List).isNotEmpty;
  }

  Future<int> countTodayReadings(int startMs) async {
    final data = await supabase
        .from(_table)
        .select('id')
        .gte('reading_date', startMs);
    return (data as List).length;
  }

  Future<int> countTodayByType(int startMs, String type) async {
    final data = await supabase
        .from(_table)
        .select('id')
        .gte('reading_date', startMs)
        .eq('reading_type', type);
    return (data as List).length;
  }

  Future<int> countOperatorTodayReadings(String operatorId, int startMs) async {
    final data = await supabase
        .from(_table)
        .select('id')
        .eq('operator_id', operatorId)
        .gte('reading_date', startMs);
    return (data as List).length;
  }

  Future<SupabaseReading?> getPreviousReading({
    required String deviceId,
    required String readingType,
    required int readingDateMs,
    required String heatNumber,
  }) async {
    if (readingType == 'day') {
      final data = await supabase
          .from(_table)
          .select()
          .eq('device_id', deviceId)
          .eq('reading_type', readingType)
          .lt('reading_date', readingDateMs)
          .order('reading_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return null;
      return SupabaseReading.fromMap(data);
    } 
    
    // For heat readings, fetch recent ones and find the immediate predecessor
    final data = await supabase
        .from(_table)
        .select()
        .eq('device_id', deviceId)
        .eq('reading_type', 'heat')
        .lte('reading_date', readingDateMs)
        .order('reading_date', ascending: false)
        .limit(50);
        
    final readings = (data as List).map((m) => SupabaseReading.fromMap(m as Map<String, dynamic>)).toList();
    if (readings.isEmpty) return null;
    
    readings.sort((a, b) {
      final dateCmp = b.readingDate.compareTo(a.readingDate);
      if (dateCmp != 0) return dateCmp;
      final ha = int.tryParse(a.heatNumber) ?? 0;
      final hb = int.tryParse(b.heatNumber) ?? 0;
      return hb.compareTo(ha);
    });
    
    final currentHeatInt = int.tryParse(heatNumber.trim());
    if (currentHeatInt == null) {
      // If no valid heat entered yet, just return the most recent one overall
      return readings.first;
    }
    
    for (final r in readings) {
      if (r.readingDate < readingDateMs) return r;
      if (r.readingDate == readingDateMs) {
        final rhInt = int.tryParse(r.heatNumber) ?? 0;
        if (rhInt < currentHeatInt) return r;
      }
    }
    
    return null;
  }

  /// Returns the most recently submitted heat reading for a device (by created_at).
  Future<SupabaseReading?> getLastHeatReading({required String deviceId}) async {
    final data = await supabase
        .from(_table)
        .select()
        .eq('device_id', deviceId)
        .eq('reading_type', 'heat')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return SupabaseReading.fromMap(data);
  }

  /// Returns the most recent heat reading where heat_number == '1' for a device,
  /// filtered to only readings on the given local calendar date (midnight UTC ms).
  Future<SupabaseReading?> getLastHeatNumberOneOnDate({
    required String deviceId,
    required int dayMidnightMs,
  }) async {
    // dayMidnightMs is start of local day in UTC ms.
    // Next day midnight = dayMidnightMs + 86400000
    final nextDayMs = dayMidnightMs + 86400000;
    final data = await supabase
        .from(_table)
        .select()
        .eq('device_id', deviceId)
        .eq('reading_type', 'heat')
        .eq('heat_number', '1')
        .gte('reading_date', dayMidnightMs)
        .lt('reading_date', nextDayMs)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return SupabaseReading.fromMap(data);
  }
}
