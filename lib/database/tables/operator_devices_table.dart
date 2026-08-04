import 'package:drift/drift.dart';
import 'operators_table.dart';
import 'devices_table.dart';

// OperatorDevices — many-to-many junction between Operators and Devices.
// Unique constraint on (operator_id, device_id) prevents duplicate assignments.
class OperatorDevices extends Table {
  TextColumn get id => text()();
  TextColumn get operatorId =>
      text().references(Operators, #id, onDelete: KeyAction.cascade)();
  TextColumn get deviceId =>
      text().references(Devices, #id, onDelete: KeyAction.cascade)();
  // UTC ms timestamp of when the assignment was made
  IntColumn get assignedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {operatorId, deviceId},
      ];
}
