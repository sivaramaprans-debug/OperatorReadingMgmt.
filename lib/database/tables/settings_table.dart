import 'package:drift/drift.dart';

// Settings table — key-value store for app and device-local settings.
// scope: 'device_local' = per-device only (e.g. theme choice)
//        'app'          = business config (e.g. session timeout) — Improvement #3
class Settings extends Table {
  // Key is the primary key (e.g. 'theme_mode', 'session_timeout_minutes')
  TextColumn get key => text()();
  TextColumn get value => text()();
  // 'device_local' | 'app'
  TextColumn get scope => text()();

  @override
  Set<Column> get primaryKey => {key};
}
