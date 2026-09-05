import 'dart:convert';

/// Represents a Plant Department / Division (e.g., Sponge Iron SID, SMS 2, SMS 3, SMS 4, CPP, RM).
class PlantDepartment {
  const PlantDepartment({
    required this.id,
    required this.name,
    required this.code,
    this.description = '',
    this.sections = const [],
    this.workTypes = const [],
    this.isActive = true,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String code;
  final String description;
  final List<String> sections;
  final List<String> workTypes;
  final bool isActive;
  final int createdAt;

  String get displayName => '$name ($code)';

  factory PlantDepartment.fromMap(Map<String, dynamic> m) {
    List<String> parseList(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) return decoded.map((e) => e.toString()).toList();
        } catch (_) {}
      }
      return [];
    }

    return PlantDepartment(
      id: m['id'] as String? ?? '',
      name: m['name'] as String? ?? '',
      code: m['code'] as String? ?? '',
      description: m['description'] as String? ?? '',
      sections: parseList(m['sections']),
      workTypes: parseList(m['work_types']),
      isActive: m['is_active'] as bool? ?? true,
      createdAt: m['created_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'description': description,
        'sections': sections,
        'work_types': workTypes,
        'is_active': isActive,
        'created_at': createdAt,
      };

  PlantDepartment copyWith({
    String? id,
    String? name,
    String? code,
    String? description,
    List<String>? sections,
    List<String>? workTypes,
    bool? isActive,
    int? createdAt,
  }) {
    return PlantDepartment(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      description: description ?? this.description,
      sections: sections ?? this.sections,
      workTypes: workTypes ?? this.workTypes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
