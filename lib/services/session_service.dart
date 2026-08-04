import 'package:flutter/widgets.dart';
import '../core/constants/app_constants.dart';

/// Manages the 15-minute idle session timeout (§0.3 / §16).
///
/// Call [recordActivity] on every meaningful user interaction.
/// Call [isExpired] before any sensitive operation or on app resume.
/// The AuthNotifier listens to [AppLifecycleListener] and calls [isExpired]
/// to trigger re-authentication when needed.
class SessionService {
  SessionService();

  int _lastActivityMs = DateTime.now().millisecondsSinceEpoch;

  /// Records a user activity, resetting the idle timer.
  void recordActivity() {
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Returns true if the session has been idle longer than the timeout.
  /// [timeoutMinutes] defaults to AppConstants.sessionTimeoutMinutes.
  bool isExpired({int? timeoutMinutes}) {
    final timeout = timeoutMinutes ?? AppConstants.sessionTimeoutMinutes;
    final elapsedMs =
        DateTime.now().millisecondsSinceEpoch - _lastActivityMs;
    return elapsedMs >= timeout * 60 * 1000;
  }

  /// Returns the number of minutes remaining before timeout (clamped to 0).
  int minutesRemaining({int? timeoutMinutes}) {
    final timeout = timeoutMinutes ?? AppConstants.sessionTimeoutMinutes;
    final elapsedMs =
        DateTime.now().millisecondsSinceEpoch - _lastActivityMs;
    final remainingMs = (timeout * 60 * 1000) - elapsedMs;
    return (remainingMs / 60000).ceil().clamp(0, timeout);
  }

  /// Resets the idle timer (call on login).
  void resetTimer() => recordActivity();
}
