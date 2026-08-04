import 'package:bcrypt/bcrypt.dart';

/// Wraps bcrypt password hashing.
/// All passwords are stored as bcrypt hashes — never plaintext.
/// Cost factor 12 is a good balance for mobile (§16 security design).
abstract final class PasswordHashingService {
  static const int _cost = 12;

  /// Hashes [plaintext] with bcrypt and returns the hash string.
  static String hash(String plaintext) {
    final salt = BCrypt.gensalt(logRounds: _cost);
    return BCrypt.hashpw(plaintext, salt);
  }

  /// Returns true if [plaintext] matches [hash].
  static bool verify(String plaintext, String hash) {
    try {
      return BCrypt.checkpw(plaintext, hash);
    } catch (_) {
      // Malformed hash — treat as mismatch
      return false;
    }
  }

  /// Hashes a recovery code (same algorithm, lower cost for UX).
  static String hashRecoveryCode(String code) {
    final salt = BCrypt.gensalt(logRounds: 10);
    return BCrypt.hashpw(code, salt);
  }

  /// Verifies a recovery code against its stored hash.
  static bool verifyRecoveryCode(String code, String hash) =>
      verify(code, hash);
}
