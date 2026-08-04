// Core error types for the Operator Reading Management System.
// All repository/use-case failures return one of these sealed types
// so the presentation layer can pattern-match without dealing with raw exceptions.

/// Base failure type. Every feature-specific failure extends this.
sealed class Failure {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Generic database I/O failure (e.g. disk full, migration error).
final class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

/// Raised when a duplicate unique-constraint entry would be created.
/// e.g. duplicate (device_id, reading_date, reading_type, heat_number).
final class DuplicateReadingFailure extends Failure {
  const DuplicateReadingFailure(super.message);

  static const DuplicateReadingFailure defaultHeat = DuplicateReadingFailure(
    'A heat reading with this shift number already exists for this device and date.',
  );

  static const DuplicateReadingFailure defaultDay = DuplicateReadingFailure(
    'A day reading already exists for this device and date.',
  );
}

/// Raised when a duplicate username or device name would be created.
final class DuplicateEntryFailure extends Failure {
  const DuplicateEntryFailure(super.message);
}

/// Raised when domain-layer validation rejects input.
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);

  /// Factory for a map of per-field errors (e.g. from a form).
  factory ValidationFailure.fields(Map<String, String> fieldErrors) {
    final msg = fieldErrors.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('; ');
    return ValidationFailure(msg);
  }
}

/// Raised by auth flows — wrong credentials, session expired, etc.
final class AuthFailure extends Failure {
  const AuthFailure(super.message);

  static const AuthFailure invalidCredentials = AuthFailure(
    'Invalid username or password.',
  );

  static const AuthFailure sessionExpired = AuthFailure(
    'Your session has expired. Please log in again.',
  );

  static const AuthFailure notAuthorized = AuthFailure(
    'You are not authorised to perform this action.',
  );
}

/// Raised when a requested entity does not exist.
final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

/// Raised when an edit-window check fails (reading no longer editable).
final class EditWindowExpiredFailure extends Failure {
  const EditWindowExpiredFailure()
      : super(
          'This reading can no longer be edited — edits are only allowed on the day the reading was created.',
        );
}
