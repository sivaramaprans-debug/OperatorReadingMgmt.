import 'dart:convert';

class LogSheetEntry {
  const LogSheetEntry({
    required this.id,
    required this.operatorId,
    required this.operatorName,
    required this.section,
    required this.logDate,
    required this.workType,
    required this.equipmentType,
    required this.description,
    this.imageUrl,
    required this.createdAt,
  });

  final String id;
  final String operatorId;
  final String operatorName;
  final String section;
  final int logDate; // milliseconds epoch
  final String workType; // Electrical, Mechanical, Maintenance, etc.
  final String equipmentType;
  final String description;
  final String? imageUrl;
  final int createdAt;

  factory LogSheetEntry.fromMap(Map<String, dynamic> m) => LogSheetEntry(
        id: m['id'] as String? ?? '',
        operatorId: m['operator_id'] as String? ?? '',
        operatorName: m['operator_name'] as String? ?? '',
        section: m['section'] as String? ?? 'General',
        logDate: m['log_date'] as int? ?? 0,
        workType: m['work_type'] as String? ?? 'General',
        equipmentType: m['equipment_type'] as String? ?? '',
        description: m['description'] as String? ?? '',
        imageUrl: m['image_url'] as String?,
        createdAt: m['created_at'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'operator_id': operatorId,
        'operator_name': operatorName,
        'section': section,
        'log_date': logDate,
        'work_type': workType,
        'equipment_type': equipmentType,
        'description': description,
        'image_url': imageUrl,
        'created_at': createdAt,
      };

  String toJson() => jsonEncode(toMap());
}
