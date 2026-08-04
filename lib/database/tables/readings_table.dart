import 'package:drift/drift.dart';
import 'operators_table.dart';
import 'devices_table.dart';

// Readings table — core transactional unit.
//
// SCHEMA v2 CHANGES:
//   - Removed readingValue and calculatedValue (raw values per unit stored in readingValues JSON).
//   - Added readingValues: JSON string mapping unit code -> raw value entered by operator.
//     e.g. {"KWH":12.5,"KVAH":10.0,"MD":5.0}
//   - readingType: 'heat' | 'day' | 'standard'
//     'standard' is used for devices where requiresHeatDay = false (no heat/day distinction).
//
// UNIQUENESS:
//   Day readings: unique on (device_id, reading_date, reading_type='day', heat_number='')
//   Heat readings: unique on (device_id, reading_date, reading_type='heat', heat_number)
//   Standard readings: unique on (device_id, reading_date, reading_type='standard', heat_number='')
//
// ON DELETE RESTRICT: forces soft-delete on Operators/Devices.
class Readings extends Table {
  TextColumn get id => text()();
  TextColumn get operatorId =>
      text().references(Operators, #id, onDelete: KeyAction.restrict)();
  TextColumn get deviceId =>
      text().references(Devices, #id, onDelete: KeyAction.restrict)();
  // 'heat' | 'day' | 'standard'
  TextColumn get readingType => text().withDefault(const Constant('standard'))();
  // Empty string for day/standard readings; shift identifier for heat readings
  TextColumn get heatNumber => text().withDefault(const Constant(''))();
  // JSON object: unit code -> raw double value entered by operator
  // e.g. {"KWH":12.5,"KVAH":10.0}
  TextColumn get readingValues => text().withDefault(const Constant('{}'))();
  // Local-midnight UTC epoch (date-only storage)
  IntColumn get readingDate => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {deviceId, readingDate, readingType, heatNumber},
      ];
}
