import 'dart:convert';

/// Represents a single editable key-value nameplate specification.
/// Both [key] (attribute name) and [value] (attribute value) are editable.
class NameplateField {
  NameplateField({
    required this.key,
    required this.value,
  });

  String key;
  String value;

  factory NameplateField.fromMap(Map<String, dynamic> m) => NameplateField(
        key: m['key'] as String? ?? '',
        value: m['value'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'key': key,
        'value': value,
      };

  NameplateField copy() => NameplateField(key: key, value: value);
}

/// Represents an equipment belonging to a plant department/division.
class PlantEquipment {
  const PlantEquipment({
    required this.id,
    required this.departmentId,
    required this.departmentName,
    this.section = 'General',
    required this.name,
    this.equipmentTag = '',
    this.nameplateDetails = const [],
    this.createdBy = '',
    this.isActive = true,
    required this.createdAt,
  });

  final String id;
  final String departmentId;
  final String departmentName;
  final String section;
  final String name;
  final String equipmentTag;
  final List<NameplateField> nameplateDetails;
  final String createdBy;
  final bool isActive;
  final int createdAt;

  String get displayName =>
      equipmentTag.isNotEmpty ? '$name ($equipmentTag)' : name;

  String get nameplateSummary {
    if (nameplateDetails.isEmpty) return 'No nameplate specifications recorded';
    return nameplateDetails
        .where((f) => f.key.trim().isNotEmpty && f.value.trim().isNotEmpty)
        .map((f) => '${f.key}: ${f.value}')
        .join(' • ');
  }

  factory PlantEquipment.fromMap(Map<String, dynamic> m) {
    List<NameplateField> parseFields(dynamic raw) {
      if (raw == null) return [];
      dynamic list = raw;
      if (raw is String) {
        try {
          list = jsonDecode(raw);
        } catch (_) {
          return [];
        }
      }
      if (list is List) {
        return list
            .whereType<Map>()
            .map((item) => NameplateField.fromMap(Map<String, dynamic>.from(item)))
            .toList();
      }
      return [];
    }

    return PlantEquipment(
      id: m['id'] as String? ?? '',
      departmentId: m['department_id'] as String? ?? '',
      departmentName: m['department_name'] as String? ?? '',
      section: m['section'] as String? ?? 'General',
      name: m['name'] as String? ?? '',
      equipmentTag: m['equipment_tag'] as String? ?? '',
      nameplateDetails: parseFields(m['nameplate_details']),
      createdBy: m['created_by'] as String? ?? '',
      isActive: m['is_active'] as bool? ?? true,
      createdAt: m['created_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'department_id': departmentId,
        'department_name': departmentName,
        'section': section,
        'name': name,
        'equipment_tag': equipmentTag,
        'nameplate_details': nameplateDetails.map((e) => e.toMap()).toList(),
        'created_by': createdBy,
        'is_active': isActive,
        'created_at': createdAt,
      };

  PlantEquipment copyWith({
    String? id,
    String? departmentId,
    String? departmentName,
    String? section,
    String? name,
    String? equipmentTag,
    List<NameplateField>? nameplateDetails,
    String? createdBy,
    bool? isActive,
    int? createdAt,
  }) {
    return PlantEquipment(
      id: id ?? this.id,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      section: section ?? this.section,
      name: name ?? this.name,
      equipmentTag: equipmentTag ?? this.equipmentTag,
      nameplateDetails: nameplateDetails ?? this.nameplateDetails,
      createdBy: createdBy ?? this.createdBy,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
