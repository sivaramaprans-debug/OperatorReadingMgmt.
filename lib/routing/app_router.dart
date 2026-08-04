import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/domain/entities/app_user.dart';
import '../features/auth/presentation/notifiers/auth_notifier.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/forgot_password_screen.dart';
import '../features/auth/presentation/screens/change_password_screen.dart';
import '../features/operators/presentation/screens/admin_operators_list_screen.dart';
import '../features/operators/presentation/screens/admin_operator_create_screen.dart';
import '../features/operators/presentation/screens/admin_operator_detail_screen.dart';
import '../features/operators/presentation/screens/admin_operator_edit_screen.dart';
import '../features/devices/presentation/screens/admin_devices_list_screen.dart';
import '../features/devices/presentation/screens/admin_device_create_screen.dart';
import '../features/devices/presentation/screens/admin_device_detail_screen.dart';
import '../features/devices/presentation/screens/admin_device_edit_screen.dart';
import '../features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import '../features/dashboard/presentation/screens/operator_dashboard_screen.dart';
import '../features/readings/presentation/screens/operator_readings_list_screen.dart';
import '../features/readings/presentation/screens/operator_reading_add_screen.dart';
import '../features/readings/presentation/screens/operator_reading_edit_screen.dart';
import '../features/readings/presentation/screens/admin_readings_list_screen.dart';
import '../features/readings/presentation/screens/admin_reading_edit_screen.dart';
import '../features/audit/presentation/screens/admin_audit_logs_screen.dart';
import '../database/repositories/supabase_operators_repository.dart';
import '../database/repositories/supabase_devices_repository.dart';
import '../database/repositories/supabase_readings_repository.dart';
import 'route_paths.dart';



// ── Router notifier (GoRouter needs a Listenable) ─────────────────────────────

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _ref.listen<AuthState>(authNotifierProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}

// ── Provider ───────────────────────────────────────────────────────────────────

/// The global GoRouter instance.
/// redirect enforces role-based access centrally (not per-screen).
final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: true,
    refreshListenable: listenable,

    // ── Central role-based redirect guard ─────────────────────────────────
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final path = state.matchedLocation;

      // Still initialising — stay on splash
      if (authState is AuthInitializing) {
        if (path != RoutePaths.splash) return RoutePaths.splash;
        return null;
      }

      // Not authenticated: only allow /login and /login/forgot-password
      if (authState is AuthUnauthenticated ||
          authState is AuthSessionExpired) {
        if (path == RoutePaths.login ||
            path == RoutePaths.forgotPassword) {
          return null;
        }
        return RoutePaths.login;
      }

      // Authenticated: block login/splash
      if (authState is AuthAuthenticated) {
        final user = authState.user;

        // Redirect away from login/splash
        if (path == RoutePaths.login ||
            path == RoutePaths.splash ||
            path == RoutePaths.forgotPassword) {
          return user.isAdmin
              ? RoutePaths.adminDashboard
              : RoutePaths.operatorDashboard;
        }

        // Operator trying to access admin routes
        if (user is OperatorUser && path.startsWith('/admin')) {
          return RoutePaths.operatorDashboard;
        }

        // Admin trying to access operator routes
        if (user is AdminUser && path.startsWith('/operator')) {
          return RoutePaths.adminDashboard;
        }
      }

      return null; // No redirect needed
    },

    errorBuilder: (context, state) => const Scaffold(body: Center(child: Text('Not Found'))),

    routes: [
      // Auth
      GoRoute(
        path: RoutePaths.splash,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const SplashScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.login,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const LoginScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const ForgotPasswordScreen(),
        ),
      ),

      // Change password (both roles)
      GoRoute(
        path: RoutePaths.operatorChangePassword,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const ChangePasswordScreen(),
        ),
      ),

      // Admin routes
      GoRoute(
        path: RoutePaths.adminDashboard,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const AdminDashboardScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.adminOperators,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const AdminOperatorsListScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.adminOperatorCreate,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const AdminOperatorCreateScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.adminOperatorDetail,
        pageBuilder: (context, state) {
          final operatorId = state.pathParameters['id']!;
          final op = state.extra as SupabaseOperator?;
          return _buildPageWithTransition(
            context,
            state,
            AdminOperatorDetailScreen(operatorId: operatorId, operator: op),
          );
        },
      ),
      GoRoute(
        path: RoutePaths.adminOperatorEdit,
        pageBuilder: (context, state) {
          final operatorId = state.pathParameters['id']!;
          final op = state.extra as SupabaseOperator?;
          return _buildPageWithTransition(
            context,
            state,
            AdminOperatorEditScreen(operatorId: operatorId, operator: op),
          );
        },
      ),
      GoRoute(
        path: RoutePaths.adminDevices,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const AdminDevicesListScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.adminDeviceCreate,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const AdminDeviceCreateScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.adminDeviceDetail,
        pageBuilder: (context, state) {
          final deviceId = state.pathParameters['id']!;
          final device = state.extra as SupabaseDevice?;
          return _buildPageWithTransition(
            context,
            state,
            AdminDeviceDetailScreen(deviceId: deviceId, device: device),
          );
        },
      ),
      GoRoute(
        path: RoutePaths.adminDeviceEdit,
        pageBuilder: (context, state) {
          final deviceId = state.pathParameters['id']!;
          final device = state.extra as SupabaseDevice?;
          return _buildPageWithTransition(
            context,
            state,
            AdminDeviceEditScreen(deviceId: deviceId, device: device),
          );
        },
      ),
      GoRoute(
        path: RoutePaths.adminReadings,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const AdminReadingsListScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.adminReadingAdd,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const AdminReadingEditScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.adminReadingEdit,
        pageBuilder: (context, state) {
          final readingId = state.pathParameters['id']!;
          final reading = state.extra as SupabaseReading?;
          return _buildPageWithTransition(
            context,
            state,
            AdminReadingEditScreen(readingId: readingId, reading: reading),
          );
        },
      ),
      GoRoute(
        path: RoutePaths.adminAuditLogs,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const AdminAuditLogsScreen(),
        ),
      ),

      // Operator routes
      GoRoute(
        path: RoutePaths.operatorDashboard,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const OperatorDashboardScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.operatorReadings,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const OperatorReadingsListScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.operatorReadingAdd,
        pageBuilder: (context, state) => _buildPageWithTransition(
          context,
          state,
          const OperatorReadingAddScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.operatorReadingEdit,
        pageBuilder: (context, state) {
          final readingId = state.pathParameters['id']!;
          final reading = state.extra as SupabaseReading?;
          return _buildPageWithTransition(
            context,
            state,
            OperatorReadingEditScreen(readingId: readingId, reading: reading),
          );
        },
      ),
    ],
  );
});

CustomTransitionPage _buildPageWithTransition(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Fade and slightly slide up
      const begin = Offset(0.0, 0.05);
      const end = Offset.zero;
      const curve = Curves.easeOutCubic;

      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
      var offsetAnimation = animation.drive(tween);

      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: offsetAnimation,
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
}
