// Domain-layer validators (§15 Validation Rules).
// Pure Dart — no Flutter/Drift imports. All validation enforced here,
// not just in form widgets, so future entry points (bulk import, etc.)
// get the same rules automatically (NFR4 / §16).

import '../constants/app_constants.dart';

/// A validated result: null = valid, non-null = error message.
typedef ValidationResult = String?;

/// All validation rules from §15. Pure Dart, no dependencies.
abstract final class Validators {
  // ── Device ────────────────────────────────────────────────────────────────

  /// Device name: required, max 100 chars (uniqueness enforced at DB level + pre-check).
  static ValidationResult deviceName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Device name is required.';
    if (value.trim().length > AppConstants.deviceNameMaxLength) {
      return 'Device name must be at most ${AppConstants.deviceNameMaxLength} characters.';
    }
    return null;
  }

  /// Multiplication factor: required, > 0, max 3 decimal places.
  static ValidationResult multiplicationFactor(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Multiplication factor is required.';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Must be a valid number.';
    if (parsed <= 0) return 'Must be greater than 0.';
    // Check decimal places
    final parts = value.trim().split('.');
    if (parts.length == 2 &&
        parts[1].length > AppConstants.multiplicationFactorDecimalPlaces) {
      return 'At most ${AppConstants.multiplicationFactorDecimalPlaces} decimal places allowed.';
    }
    return null;
  }

  // ── Operator ──────────────────────────────────────────────────────────────

  /// Operator full name: required.
  static ValidationResult fullName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Full name is required.';
    return null;
  }

  /// Username: required, 4–30 chars, alphanumeric + ._-
  static ValidationResult username(String? value) {
    if (value == null || value.trim().isEmpty) return 'Username is required.';
    final trimmed = value.trim();
    if (trimmed.length < AppConstants.usernameMinLength) {
      return 'Must be at least ${AppConstants.usernameMinLength} characters.';
    }
    if (trimmed.length > AppConstants.usernameMaxLength) {
      return 'Must be at most ${AppConstants.usernameMaxLength} characters.';
    }
    final allowed = RegExp(r'^[a-zA-Z0-9._\-]+$');
    if (!allowed.hasMatch(trimmed)) {
      return 'Only letters, numbers, . _ - are allowed.';
    }
    return null;
  }

  /// Password: required, min 8 chars, at least 1 letter + 1 number.
  static ValidationResult password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    if (value.length < AppConstants.passwordMinLength) {
      return 'Must be at least ${AppConstants.passwordMinLength} characters.';
    }
    if (!RegExp(r'[a-zA-Z]').hasMatch(value)) {
      return 'Must contain at least one letter.';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Must contain at least one number.';
    }
    return null;
  }

  /// Confirm password: must match the original.
  static ValidationResult confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please confirm your password.';
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  /// Phone number: required, 10–15 digits, optional leading +.
  static ValidationResult phoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required.';
    final trimmed = value.trim();
    final phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');
    if (!phoneRegex.hasMatch(trimmed)) {
      return 'Enter a valid phone number (10–15 digits, optional +).';
    }
    return null;
  }

  // ── Reading ───────────────────────────────────────────────────────────────

  /// Reading value: required, >= 0, numeric.
  static ValidationResult readingValue(String? value) {
    if (value == null || value.trim().isEmpty) return 'Reading value is required.';
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Must be a valid number.';
    if (parsed < 0) return 'Reading value cannot be negative.';
    return null;
  }

  /// Heat number (shift ID): required when reading type is heat.
  static ValidationResult heatNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Shift / Heat number is required.';
    }
    return null;
  }

  /// Reading date: required, not in the future.
  /// [readingDateMs] is the local-midnight epoch.
  static ValidationResult readingDate(int? readingDateMs) {
    if (readingDateMs == null) return 'Reading date is required.';
    final date = DateTime.fromMillisecondsSinceEpoch(readingDateMs, isUtc: true)
        .toLocal();
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final dateMidnight = DateTime(date.year, date.month, date.day);
    if (dateMidnight.isAfter(todayMidnight)) {
      return 'Reading date cannot be in the future.';
    }
    return null;
  }

  // ── Generic ───────────────────────────────────────────────────────────────

  /// Returns true if [value] is non-null and non-empty (for optional validation chains).
  static bool isNotEmpty(String? value) =>
      value != null && value.trim().isNotEmpty;

  /// Required field helper for plain "must not be empty" checks.
  static ValidationResult required(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) return '$fieldName is required.';
    return null;
  }
}
