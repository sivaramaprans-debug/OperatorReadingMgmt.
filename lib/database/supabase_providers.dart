import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repositories/supabase_operators_repository.dart';
import 'repositories/supabase_devices_repository.dart';
import 'repositories/supabase_readings_repository.dart';
import 'repositories/supabase_audit_repository.dart';
import 'repositories/supabase_settings_repository.dart';

/// Global Supabase repository providers — use these instead of the Drift DAO providers.

final supabaseOperatorsRepoProvider =
    Provider<SupabaseOperatorsRepository>((ref) => SupabaseOperatorsRepository());

final supabaseDevicesRepoProvider =
    Provider<SupabaseDevicesRepository>((ref) => SupabaseDevicesRepository());

final supabaseReadingsRepoProvider =
    Provider<SupabaseReadingsRepository>((ref) => SupabaseReadingsRepository());

final supabaseAuditRepoProvider =
    Provider<SupabaseAuditRepository>((ref) => SupabaseAuditRepository());

final supabaseSettingsRepoProvider =
    Provider<SupabaseSettingsRepository>((ref) => SupabaseSettingsRepository());

// ── Convenience FutureProviders ─────────────────────────────────────────────

/// All active operators (for admin UI dropdowns / lists).
final allOperatorsSupabaseProvider =
    FutureProvider.autoDispose<List<SupabaseOperator>>((ref) {
  return ref.watch(supabaseOperatorsRepoProvider).getAll();
});

/// All devices (active + inactive, for admin UI).
final allDevicesSupabaseProvider =
    FutureProvider.autoDispose<List<SupabaseDevice>>((ref) {
  return ref.watch(supabaseDevicesRepoProvider).getAll();
});

/// Active devices only (for operator UI).
final activeDevicesSupabaseProvider =
    FutureProvider.autoDispose<List<SupabaseDevice>>((ref) {
  return ref.watch(supabaseDevicesRepoProvider).getActive();
});
