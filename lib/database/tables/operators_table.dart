import 'package:drift/drift.dart';

// Operators table.
// status CHECK: 'active' | 'inactive'.
// is_deleted: soft-delete flag (never hard-delete due to FK from Readings — Improvement #6).
class Operators extends Table {
  TextColumn get id => text()();
  TextColumn get fullName => text()();
  TextColumn get username => text().withLength(min: 4, max: 30).unique()();
  TextColumn get passwordHash => text()();
  TextColumn get phoneNumber => text()();
  // 'active' | 'inactive'
  TextColumn get status =>
      text().withDefault(const Constant('active'))();
  // Soft delete — never hard-delete due to FK from Readings
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
