// Named route path constants for GoRouter.
// All routes in one place — no magic strings scattered across the codebase.
abstract final class RoutePaths {
  // Splash / initial
  static const String splash = '/splash';

  // Auth
  static const String login = '/login';
  static const String forgotPassword = '/login/forgot-password';

  // Admin routes
  static const String adminDashboard = '/admin/dashboard';
  static const String adminOperators = '/admin/operators';
  static const String adminOperatorDetail = '/admin/operators/:id';
  static const String adminOperatorEdit = '/admin/operators/:id/edit';
  static const String adminOperatorCreate = '/admin/operators/create';
  static const String adminDevices = '/admin/devices';
  static const String adminDeviceDetail = '/admin/devices/:id';
  static const String adminDeviceEdit = '/admin/devices/:id/edit';
  static const String adminDeviceCreate = '/admin/devices/create';
  static const String adminReadings = '/admin/readings';
  static const String adminReadingAdd = '/admin/readings/add';
  static const String adminReadingEdit = '/admin/readings/:id/edit';
  static const String adminAuditLogs = '/admin/audit-logs';

  // Operator routes
  static const String operatorDashboard = '/operator/dashboard';
  static const String operatorReadings = '/operator/readings';
  static const String operatorReadingAdd = '/operator/readings/add';
  static const String operatorReadingEdit = '/operator/readings/:id/edit';
  static const String operatorChangePassword = '/operator/change-password';

  // Helpers — build concrete paths with IDs
  static String adminOperatorDetailPath(String id) =>
      '/admin/operators/$id';
  static String adminOperatorEditPath(String id) =>
      '/admin/operators/$id/edit';
  static String adminDeviceDetailPath(String id) =>
      '/admin/devices/$id';
  static String adminDeviceEditPath(String id) =>
      '/admin/devices/$id/edit';
  static String adminReadingEditPath(String id) =>
      '/admin/readings/$id/edit';
  static String operatorReadingEditPath(String id) =>
      '/operator/readings/$id/edit';
}
