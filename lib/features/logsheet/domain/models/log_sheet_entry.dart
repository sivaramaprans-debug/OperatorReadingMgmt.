import 'dart:convert';

class LogSheetEntry {
  const LogSheetEntry({
    required this.id,
    this.departmentId,
    this.departmentName,
    required this.operatorId,
    required this.operatorName,
    required this.section,
    required this.logDate,
    required this.workType,
    this.equipmentId,
    this.equipmentType = '',
    this.nameplateSnapshot,
    required this.description,
    this.imageUrl,
    required this.createdAt,
  });

  final String id;
  final String? departmentId;
  final String? departmentName;
  final String operatorId;
  final String operatorName;
  final String section;
  final int logDate; // milliseconds epoch
  final String workType; // Breakdown Repair, Maintenance, Electrical, etc.
  final String? equipmentId;
  final String equipmentType;
  final String? nameplateSnapshot;
  final String description;
  final String? imageUrl;
  final int createdAt;

  bool get hasEquipment => equipmentType.trim().isNotEmpty && equipmentType != 'General / None';

  factory LogSheetEntry.fromMap(Map<String, dynamic> m) => LogSheetEntry(
        id: m['id'] as String? ?? '',
        departmentId: m['department_id'] as String?,
        departmentName: m['department_name'] as String?,
        operatorId: m['operator_id'] as String? ?? '',
        operatorName: m['operator_name'] as String? ?? '',
        section: m['section'] as String? ?? 'General',
        logDate: m['log_date'] as int? ?? 0,
        workType: m['work_type'] as String? ?? 'General',
        equipmentId: m['equipment_id'] as String?,
        equipmentType: m['equipment_type'] as String? ?? '',
        nameplateSnapshot: m['nameplate_snapshot'] != null
            ? (m['nameplate_snapshot'] is String
                ? m['nameplate_snapshot'] as String
                : jsonEncode(m['nameplate_snapshot']))
            : null,
        description: m['description'] as String? ?? '',
        imageUrl: m['image_url'] as String?,
        createdAt: m['created_at'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        if (departmentId != null) 'department_id': departmentId,
        if (departmentName != null) 'department_name': departmentName,
        'operator_id': operatorId,
        'operator_name': operatorName,
        'section': section,
        'log_date': logDate,
        'work_type': workType,
        if (equipmentId != null) 'equipment_id': equipmentId,
        'equipment_type': equipmentType,
        if (nameplateSnapshot != null) 'nameplate_snapshot': nameplateSnapshot,
        'description': description,
        'image_url': imageUrl,
        'created_at': createdAt,
      };

  String toJson() => jsonEncode(toMap());
}
