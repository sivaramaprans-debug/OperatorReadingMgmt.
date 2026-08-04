import 'package:drift/drift.dart';

// Admins table — stores the Admin accounts.
// Only one Admin is seeded by default (admin/admin123 hashed).
// UUID TEXT primary key (sync-ready per Improvement #1).
// recovery_code_hash: local recovery code for Admin self-reset (§0.4a).
class Admins extends Table {
  // UUID stored as TEXT
  TextColumn get id => text()();
  TextColumn get username => text().withLength(max: 30).unique()();
  TextColumn get passwordHash => text()();
  // Nullable: set once on first Admin setup, shown once, stored hashed
  TextColumn get recoveryCodeHash => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
