import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_audit_repository.dart';
import '../../../../services/audit_service.dart';
import '../../../../services/secure_storage_service.dart';
import '../../../../services/session_service.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/seed_admin_usecase.dart';

// ── Service & Repository providers ───────────────────────────────────────────────

final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

final sessionServiceProvider = Provider<SessionService>(
  (ref) => SessionService(),
);

final auditServiceProvider = Provider<AuditService>((ref) {
  final auditRepo = ref.watch(supabaseAuditRepoProvider);
  return AuditService.fromSupabase(auditRepo);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    operatorsRepo: ref.watch(supabaseOperatorsRepoProvider),
    secureStorage: ref.watch(secureStorageProvider),
  );
});

final loginUseCaseProvider = Provider(
  (ref) => LoginUseCase(ref.watch(authRepositoryProvider)),
);

final logoutUseCaseProvider = Provider(
  (ref) => LogoutUseCase(ref.watch(authRepositoryProvider)),
);

final seedAdminUseCaseProvider = Provider(
  (ref) => SeedAdminUseCase(ref.watch(authRepositoryProvider)),
);

// ── AuthState ────────────────────────────────────────────────────────────────────

/// App-wide auth state. GoRouter reads this to enforce role-based routing.
sealed class AuthState {
  const AuthState();
}

/// Auth is being initialised (splash state).
final class AuthInitializing extends AuthState {
  const AuthInitializing();
}

/// No active session — show login screen.
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Active authenticated session.
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final AppUser user;
}

/// Session expired (idle timeout). Show login with a message.
final class AuthSessionExpired extends AuthState {
  const AuthSessionExpired();
}

// ── AuthNotifier ────────────────────────────────────────────────────────────────

/// App-wide auth notifier. GoRouter's refreshListenable watches this.
/// Manages: session restore, login, logout, idle-timeout expiry.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Start initialising; initialize() is called from app startup.
    return const AuthInitializing();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);
  SessionService get _session => ref.read(sessionServiceProvider);

  /// Called once at startup (from SplashScreen) to restore session.
  Future<void> initialize() async {
    state = const AuthInitializing();
    try {
      // Seed admin first (idempotent)
      await ref.read(seedAdminUseCaseProvider).call();
      // Restore session
      final user = await _repo.restoreSession();
      if (user != null) {
        state = AuthAuthenticated(user);
        _session.resetTimer();
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  /// Called by the login screen on submit.
  Future<String?> login(String username, String password) async {
    final useCase = ref.read(loginUseCaseProvider);
    final (user, failure) = await useCase(username: username, password: password);
    if (failure != null) return failure.message;
    if (user != null) {
      _session.resetTimer();
      state = AuthAuthenticated(user);
    }
    return null; // null = success
  }

  /// Called by logout button or session expiry.
  Future<void> logout() async {
    await _repo.logout();
    state = const AuthUnauthenticated();
  }

  /// Called by app-lifecycle observer on resume.
  /// If idle for > 15 min, transitions to expired state.
  void checkIdleTimeout() {
    if (state is! AuthAuthenticated) return;
    if (_session.isExpired()) {
      _repo.logout();
      state = const AuthSessionExpired();
    }
  }

  /// Records user activity to reset the idle timer.
  void recordActivity() {
    if (state is AuthAuthenticated) {
      _session.recordActivity();
    }
  }

  /// Returns the currently authenticated user, or null.
  AppUser? get currentUser {
    final s = state;
    return s is AuthAuthenticated ? s.user : null;
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
