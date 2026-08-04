import 'package:drift/drift.dart';

// Devices table.
// multiplication_factor: REAL > 0, stored at full precision, displayed to 3dp.
// matrix: comma-separated list of assigned unit codes, e.g. "KWH,KVAH,MD"
// requires_heat_day: whether this device uses Heat/Day reading categorization.
// is_deleted: soft-delete (historical readings must still reference this row).
class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100).unique()();
  // > 0 enforced in domain layer (Drift doesn't support CHECK natively via annotations)
  RealColumn get multiplicationFactor => real()();
  // Comma-separated unit list, e.g. "KWH,KVAH,MD" — empty means no matrix assigned
  TextColumn get matrix => text().withDefault(const Constant(''))();
  // Comma-separated unit list specifically for Day readings when requiresHeatDay is true
  TextColumn get dayMatrix => text().withDefault(const Constant(''))();
  // JSON map of {"KWH": 1200.0} — per-unit factor for Heat (or standard) matrix units
  TextColumn get heatUnitFactors => text().withDefault(const Constant('{}'))();
  // JSON map of {"KWH": 1200.0} — per-unit factor for Day matrix units
  TextColumn get dayUnitFactors => text().withDefault(const Constant('{}'))();
  // Whether operator must choose Heat or Day type when submitting readings
  BoolColumn get requiresHeatDay => boolean().withDefault(const Constant(false))();
  // 'active' | 'inactive'
  TextColumn get status =>
      text().withDefault(const Constant('active'))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
