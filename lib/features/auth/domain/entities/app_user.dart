// Domain entity representing the authenticated user.
// Sealed so the presentation layer can exhaustively pattern-match on role.
// Pure Dart — no Flutter or Drift imports.

sealed class AppUser {
  const AppUser({
    required this.id,
    required this.username,
  });

  final String id;
  final String username;

  /// The role string stored in SecureStorage and AuditLogs.
  String get role;

  /// True if this user can access admin routes.
  bool get isAdmin => this is AdminUser;

  /// True if this user can access operator routes.
  bool get isOperator => this is OperatorUser;
}

/// An authenticated Admin account.
final class AdminUser extends AppUser {
  const AdminUser({
    required super.id,
    required super.username,
  });

  @override
  String get role => 'admin';

  @override
  String toString() => 'AdminUser(id: $id, username: $username)';
}

/// An authenticated Operator account.
final class OperatorUser extends AppUser {
  const OperatorUser({
    required super.id,
    required super.username,
    required this.fullName,
  });

  final String fullName;

  @override
  String get role => 'operator';

  @override
  String toString() =>
      'OperatorUser(id: $id, username: $username, fullName: $fullName)';
}
