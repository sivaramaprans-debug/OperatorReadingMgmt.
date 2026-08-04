import 'package:drift/drift.dart';

// AuditLogs table — immutable append-only log of all mutations.
// Written in the SAME transaction as the mutation it records (NFR2 / §16).
// actor_role: 'admin' | 'operator'
// action examples: 'reading.create', 'operator.deactivate', 'device.edit'
class AuditLogs extends Table {
  TextColumn get id => text()();
  // The Admin or Operator ID who performed the action
  TextColumn get actorId => text()();
  // 'admin' | 'operator'
  TextColumn get actorRole => text()();
  // e.g. 'reading.create', 'operator.deactivate', 'password.reset'
  TextColumn get action => text()();
  // e.g. 'reading', 'operator', 'device'
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  // Optional JSON blob: before/after snapshot for edits, param details
  TextColumn get metadataJson => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  // AuditLogs are never updated or deleted
  @override
  bool get withoutRowId => false;
}
