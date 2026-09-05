import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../../database/supabase_client.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../domain/models/plant_equipment.dart';

class SupabasePlantEquipmentsRepository {
  static const _table = 'plant_equipments';
  final _uuid = const Uuid();

  // In-memory fallback if table is not yet created or offline
  static final List<PlantEquipment> defaultEquipments = [
    PlantEquipment(
      id: 'eqp-sid-01',
      departmentId: 'dept-sid',
      departmentName: 'Sponge Iron Division',
      section: 'Kiln Area',
      name: 'Kiln Main Drive Motor',
      equipmentTag: 'MTR-KILN-01',
      nameplateDetails: [
        NameplateField(key: 'Make', value: 'ABB'),
        NameplateField(key: 'Power', value: '160 kW'),
        NameplateField(key: 'Voltage', value: '415 V'),
        NameplateField(key: 'Current', value: '275 A'),
        NameplateField(key: 'RPM', value: '1480'),
        NameplateField(key: 'Frame', value: '315M'),
        NameplateField(key: 'DE Bearing', value: '6319 C3'),
        NameplateField(key: 'NDE Bearing', value: '6316 C3'),
      ],
      createdBy: 'admin',
      isActive: true,
      createdAt: 1725532800000,
    ),
    PlantEquipment(
      id: 'eqp-sid-02',
      departmentId: 'dept-sid',
      departmentName: 'Sponge Iron Division',
      section: 'ESP & Bag House',
      name: 'ID Fan Motor',
      equipmentTag: 'MTR-IDF-01',
      nameplateDetails: [
        NameplateField(key: 'Make', value: 'Siemens'),
        NameplateField(key: 'Power', value: '250 kW'),
        NameplateField(key: 'Voltage', value: '415 V'),
        NameplateField(key: 'Current', value: '420 A'),
        NameplateField(key: 'RPM', value: '980'),
        NameplateField(key: 'DE Bearing', value: 'NU 322'),
        NameplateField(key: 'NDE Bearing', value: '6320 C3'),
      ],
      createdBy: 'admin',
      isActive: true,
      createdAt: 1725532800001,
    ),
    PlantEquipment(
      id: 'eqp-sms2-01',
      departmentId: 'dept-sms2',
      departmentName: 'Steel Melting Shop 2',
      section: 'Induction Furnace',
      name: 'Furnace Transformer 1',
      equipmentTag: 'XFMR-SMS2-01',
      nameplateDetails: [
        NameplateField(key: 'Capacity', value: '16 MVA'),
        NameplateField(key: 'Primary Voltage', value: '33 kV'),
        NameplateField(key: 'Secondary Voltage', value: '1050 V'),
        NameplateField(key: 'Make', value: 'Voltamp'),
        NameplateField(key: 'Cooling', value: 'OFWF'),
        NameplateField(key: 'Vector Group', value: 'Dyn11'),
      ],
      createdBy: 'admin',
      isActive: true,
      createdAt: 1725532800002,
    ),
    PlantEquipment(
      id: 'eqp-sms2-02',
      departmentId: 'dept-sms2',
      departmentName: 'Steel Melting Shop 2',
      section: 'CCM Area',
      name: 'Mould Oscillation Motor',
      equipmentTag: 'MTR-OSC-01',
      nameplateDetails: [
        NameplateField(key: 'Make', value: 'Bharat Bijlee'),
        NameplateField(key: 'Power', value: '11 kW'),
        NameplateField(key: 'RPM', value: '1440'),
        NameplateField(key: 'Drive Type', value: 'VFD Duty'),
      ],
      createdBy: 'admin',
      isActive: true,
      createdAt: 1725532800003,
    ),
  ];

  /// Fetch equipments filtered by department and optional section.
  Future<List<PlantEquipment>> getByDepartment({
    String? departmentId,
    String? section,
    bool activeOnly = true,
  }) async {
    try {
      var query = supabase.from(_table).select();
      if (departmentId != null && departmentId.isNotEmpty && departmentId != 'All') {
        query = query.eq('department_id', departmentId);
      }
      if (section != null && section.isNotEmpty && section != 'All') {
        query = query.eq('section', section);
      }
      if (activeOnly) {
        query = query.eq('is_active', true);
      }

      final data = await query.order('name');
      final list = (data as List)
          .map((m) => PlantEquipment.fromMap(m as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty) return list;

      // Fallback in-memory list
      return defaultEquipments.where((e) {
        if (activeOnly && !e.isActive) return false;
        if (departmentId != null && departmentId.isNotEmpty && departmentId != 'All' && e.departmentId != departmentId) {
          return false;
        }
        if (section != null && section.isNotEmpty && section != 'All' && e.section != section) {
          return false;
        }
        return true;
      }).toList();
    } catch (e) {
      debugPrint('SupabasePlantEquipmentsRepository.getByDepartment error: $e');
      return defaultEquipments.where((e) {
        if (activeOnly && !e.isActive) return false;
        if (departmentId != null && departmentId.isNotEmpty && departmentId != 'All' && e.departmentId != departmentId) {
          return false;
        }
        if (section != null && section.isNotEmpty && section != 'All' && e.section != section) {
          return false;
        }
        return true;
      }).toList();
    }
  }

  /// Create a new equipment with dynamic nameplate details.
  Future<String> create({
    required String departmentId,
    required String departmentName,
    String section = 'General',
    required String name,
    String equipmentTag = '',
    List<NameplateField> nameplateDetails = const [],
    String createdBy = '',
  }) async {
    final id = _uuid.v4();
    final now = AppDateUtils.nowUtcMs();

    final row = {
      'id': id,
      'department_id': departmentId,
      'department_name': departmentName,
      'section': section,
      'name': name.trim(),
      'equipment_tag': equipmentTag.trim(),
      'nameplate_details': nameplateDetails.map((e) => e.toMap()).toList(),
      'created_by': createdBy,
      'is_active': true,
      'created_at': now,
    };

    try {
      await supabase.from(_table).insert(row);
    } catch (e) {
      debugPrint('Error creating equipment in Supabase: $e');
      defaultEquipments.add(PlantEquipment(
        id: id,
        departmentId: departmentId,
        departmentName: departmentName,
        section: section,
        name: name.trim(),
        equipmentTag: equipmentTag.trim(),
        nameplateDetails: nameplateDetails,
        createdBy: createdBy,
        isActive: true,
        createdAt: now,
      ));
    }
    return id;
  }

  /// Update equipment and its nameplate specifications.
  Future<void> update(
    String id, {
    String? name,
    String? equipmentTag,
    String? section,
    List<NameplateField>? nameplateDetails,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name.trim();
    if (equipmentTag != null) updates['equipment_tag'] = equipmentTag.trim();
    if (section != null) updates['section'] = section;
    if (nameplateDetails != null) {
      updates['nameplate_details'] = nameplateDetails.map((e) => e.toMap()).toList();
    }
    if (isActive != null) updates['is_active'] = isActive;

    try {
      await supabase.from(_table).update(updates).eq('id', id);
    } catch (e) {
      debugPrint('Error updating equipment in Supabase: $e');
      final index = defaultEquipments.indexWhere((e) => e.id == id);
      if (index != -1) {
        final existing = defaultEquipments[index];
        defaultEquipments[index] = existing.copyWith(
          name: name,
          equipmentTag: equipmentTag,
          section: section,
          nameplateDetails: nameplateDetails,
          isActive: isActive,
        );
      }
    }
  }

  /// Deactivate an equipment.
  Future<void> delete(String id) async {
    try {
      await supabase.from(_table).update({'is_active': false}).eq('id', id);
    } catch (e) {
      debugPrint('Error deactivating equipment: $e');
      defaultEquipments.removeWhere((e) => e.id == id);
    }
  }
}
