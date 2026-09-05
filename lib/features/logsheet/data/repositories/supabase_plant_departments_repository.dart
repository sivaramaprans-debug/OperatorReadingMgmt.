import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../../database/supabase_client.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../domain/models/plant_department.dart';

class SupabasePlantDepartmentsRepository {
  static const _table = 'plant_departments';
  final _uuid = const Uuid();

  // In-memory fallback if Supabase table is not yet created or offline
  static final List<PlantDepartment> defaultDepartments = [
    const PlantDepartment(
      id: 'dept-sid',
      name: 'Sponge Iron Division',
      code: 'SID',
      description: 'Direct Reduced Iron / Rotary Kiln Plant Area',
      sections: [
        'Kiln Area',
        'Cooler Area',
        'ESP & Bag House',
        'Coal Injection',
        'Raw Material Feed',
        'Product Handling',
        'Utilities',
      ],
      workTypes: [
        'Breakdown Repair',
        'Preventive Maintenance',
        'Inspection',
        'Cleaning / Routine',
        'Electrical',
        'Mechanical',
        'Operation',
        'Other',
      ],
      isActive: true,
      createdAt: 1725532800000,
    ),
    const PlantDepartment(
      id: 'dept-sms2',
      name: 'Steel Melting Shop 2',
      code: 'SMS 2',
      description: 'Induction Furnace & Continuous Casting Area (Unit 2)',
      sections: [
        'Induction Furnace',
        'CCM Area',
        'Ladle Refining',
        'EOT Crane',
        'Cooling Water System',
        'Substation / Transformer Area',
        'General',
      ],
      workTypes: [
        'Breakdown Repair',
        'Preventive Maintenance',
        'Inspection',
        'Cleaning / Routine',
        'Electrical',
        'Mechanical',
        'Operation',
        'Other',
      ],
      isActive: true,
      createdAt: 1725532800001,
    ),
    const PlantDepartment(
      id: 'dept-sms3',
      name: 'Steel Melting Shop 3',
      code: 'SMS 3',
      description: 'Induction Furnace & Continuous Casting Area (Unit 3)',
      sections: [
        'Induction Furnace',
        'CCM Area',
        'Ladle Refining',
        'EOT Crane',
        'Cooling Water System',
        'Substation / Transformer Area',
        'General',
      ],
      workTypes: [
        'Breakdown Repair',
        'Preventive Maintenance',
        'Inspection',
        'Cleaning / Routine',
        'Electrical',
        'Mechanical',
        'Operation',
        'Other',
      ],
      isActive: true,
      createdAt: 1725532800002,
    ),
    const PlantDepartment(
      id: 'dept-sms4',
      name: 'Steel Melting Shop 4',
      code: 'SMS 4',
      description: 'Induction Furnace & Continuous Casting Area (Unit 4)',
      sections: [
        'Induction Furnace',
        'CCM Area',
        'Ladle Refining',
        'EOT Crane',
        'Cooling Water System',
        'Substation / Transformer Area',
        'General',
      ],
      workTypes: [
        'Breakdown Repair',
        'Preventive Maintenance',
        'Inspection',
        'Cleaning / Routine',
        'Electrical',
        'Mechanical',
        'Operation',
        'Other',
      ],
      isActive: true,
      createdAt: 1725532800003,
    ),
    const PlantDepartment(
      id: 'dept-cpp',
      name: 'Captive Power Plant',
      code: 'CPP',
      description: 'Thermal / Waste Heat Recovery Power Plant',
      sections: [
        'AFBC Boiler',
        'WHRB Boiler',
        'Turbine & Generator',
        'Cooling Tower',
        'DM Water Plant',
        'Coal & Ash Handling',
        'Switchyard',
      ],
      workTypes: [
        'Breakdown Repair',
        'Preventive Maintenance',
        'Inspection',
        'Cleaning / Routine',
        'Electrical',
        'Mechanical',
        'Operation',
        'Other',
      ],
      isActive: true,
      createdAt: 1725532800004,
    ),
    const PlantDepartment(
      id: 'dept-rm',
      name: 'Rolling Mill',
      code: 'RM',
      description: 'Rebar & Structural Rolling Mill Area',
      sections: [
        'Reheating Furnace',
        'Roughing Mill',
        'Intermediate Mill',
        'Finishing Mill',
        'Cooling Bed',
        'Shearing & Bundling',
        'General',
      ],
      workTypes: [
        'Breakdown Repair',
        'Preventive Maintenance',
        'Inspection',
        'Cleaning / Routine',
        'Electrical',
        'Mechanical',
        'Operation',
        'Other',
      ],
      isActive: true,
      createdAt: 1725532800005,
    ),
  ];

  /// Fetch all active departments.
  Future<List<PlantDepartment>> getAll({bool activeOnly = true}) async {
    try {
      var query = supabase.from(_table).select();
      if (activeOnly) {
        query = query.eq('is_active', true);
      }
      final data = await query.order('name');
      final list = (data as List)
          .map((m) => PlantDepartment.fromMap(m as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty) return list;
      return defaultDepartments.where((d) => !activeOnly || d.isActive).toList();
    } catch (e) {
      debugPrint('SupabasePlantDepartmentsRepository.getAll error: $e');
      return defaultDepartments.where((d) => !activeOnly || d.isActive).toList();
    }
  }

  /// Fetch a single department by ID.
  Future<PlantDepartment?> findById(String id) async {
    try {
      final data = await supabase.from(_table).select().eq('id', id).maybeSingle();
      if (data != null) {
        return PlantDepartment.fromMap(data);
      }
    } catch (_) {}
    return defaultDepartments.where((d) => d.id == id).firstOrNull;
  }

  /// Create a new plant department.
  Future<String> create({
    required String name,
    required String code,
    String description = '',
    List<String> sections = const [],
    List<String> workTypes = const [],
  }) async {
    final id = _uuid.v4();
    final now = AppDateUtils.nowUtcMs();

    try {
      await supabase.from(_table).insert({
        'id': id,
        'name': name.trim(),
        'code': code.trim().toUpperCase(),
        'description': description.trim(),
        'sections': sections,
        'work_types': workTypes,
        'is_active': true,
        'created_at': now,
      });
    } catch (e) {
      debugPrint('Error inserting department in Supabase: $e');
      // If table not created yet, add locally to fallback list
      defaultDepartments.add(PlantDepartment(
        id: id,
        name: name.trim(),
        code: code.trim().toUpperCase(),
        description: description.trim(),
        sections: sections,
        workTypes: workTypes,
        isActive: true,
        createdAt: now,
      ));
    }
    return id;
  }

  /// Update an existing department.
  Future<void> update(
    String id, {
    String? name,
    String? code,
    String? description,
    List<String>? sections,
    List<String>? workTypes,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name.trim();
    if (code != null) updates['code'] = code.trim().toUpperCase();
    if (description != null) updates['description'] = description.trim();
    if (sections != null) updates['sections'] = sections;
    if (workTypes != null) updates['work_types'] = workTypes;
    if (isActive != null) updates['is_active'] = isActive;

    try {
      await supabase.from(_table).update(updates).eq('id', id);
    } catch (e) {
      debugPrint('Error updating department in Supabase: $e');
      final index = defaultDepartments.indexWhere((d) => d.id == id);
      if (index != -1) {
        final existing = defaultDepartments[index];
        defaultDepartments[index] = existing.copyWith(
          name: name,
          code: code,
          description: description,
          sections: sections,
          workTypes: workTypes,
          isActive: isActive,
        );
      }
    }
  }

  /// Deactivate / remove a department.
  Future<void> delete(String id) async {
    try {
      await supabase.from(_table).update({'is_active': false}).eq('id', id);
    } catch (e) {
      debugPrint('Error deactivating department: $e');
      defaultDepartments.removeWhere((d) => d.id == id);
    }
  }
}
