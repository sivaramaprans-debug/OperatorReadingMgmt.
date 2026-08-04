// App-wide constants for the Operator Reading Management System.

/// Application-level constants (non-sensitive).
abstract final class AppConstants {
  // App identity
  static const String appName = 'Operator Reading Mgmt';
  static const String appVersion = '1.0.0';

  // Default admin credentials (seeded on first launch, hashed — never stored plain)
  static const String defaultAdminUsername = 'admin';
  static const String defaultAdminPassword = 'admin123';

  // Session
  /// Idle timeout in minutes before re-authentication is required (§0.3 / §16).
  static const int sessionTimeoutMinutes = 15;

  // Database
  static const String databaseFileName = 'operator_reading_mgmt.db';
  static const int currentSchemaVersion = 4;

  // Settings keys (stored in Settings table)
  static const String settingKeyThemeMode = 'theme_mode'; // device_local scope
  static const String settingKeySessionTimeout = 'session_timeout_minutes'; // app scope

  // SecureStorage keys
  static const String secureKeySessionToken = 'session_token';
  static const String secureKeyActiveUserId = 'active_user_id';
  static const String secureKeyActiveUserRole = 'active_user_role';
  static const String secureKeyAdminRecoveryCode = 'admin_recovery_code_hash';

  // Pagination
  static const int defaultPageSize = 30;
  static const int auditLogPageSize = 20;

  // Validation limits
  static const int deviceNameMaxLength = 100;
  static const int usernameMinLength = 4;
  static const int usernameMaxLength = 30;
  static const int passwordMinLength = 8;
  static const int phoneMinDigits = 10;
  static const int phoneMaxDigits = 15;

  // Multiplication factor display precision
  static const int multiplicationFactorDecimalPlaces = 3;

  // All assignable matrix units for devices
  static const List<String> matrixUnits = [
    'KWH', 'KWHLT', 'KVAH', 'PF', 'MD', 'Q1', 'Q2', 'KW', 'MF VOLTAGE', 'FREQUENCY',
  ];
}
