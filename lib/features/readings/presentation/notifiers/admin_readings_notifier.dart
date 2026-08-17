import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/supabase_providers.dart';

class AdminReadingsFilter {
  const AdminReadingsFilter({
    this.operatorId,
    this.deviceIds = const [],
    this.readingType,
    this.fromDateMs,
    this.toDateMs,
  });

  final String? operatorId;
  final List<String> deviceIds;
  final String? readingType;
  final int? fromDateMs;
  final int? toDateMs;
}

final adminReadingsFilterProvider =
    StateProvider<AdminReadingsFilter>((ref) => const AdminReadingsFilter());

final adminReadingsProvider =
    FutureProvider.autoDispose<List<SupabaseReadingWithDetails>>((ref) async {
  final filter = ref.watch(adminReadingsFilterProvider);
  final repo = ref.watch(supabaseReadingsRepoProvider);

  return repo.search(
    deviceIds: filter.deviceIds.isNotEmpty ? filter.deviceIds : null,
    readingType: filter.readingType,
    fromDateMs: filter.fromDateMs,
    toDateMs: filter.toDateMs,
    limit: 500,
  );
});

final adminDaySummaryReadingsProvider =
    FutureProvider.autoDispose<List<SupabaseReadingWithDetails>>((ref) async {
  final filter = ref.watch(adminReadingsFilterProvider);
  final repo = ref.watch(supabaseReadingsRepoProvider);

  return repo.search(
    deviceIds: filter.deviceIds.isNotEmpty ? filter.deviceIds : null,
    readingType: 'day',
    fromDateMs: filter.fromDateMs,
    toDateMs: filter.toDateMs,
    limit: 500,
  );
});

final adminHeatSummaryReadingsProvider =
    FutureProvider.autoDispose<List<SupabaseReadingWithDetails>>((ref) async {
  final filter = ref.watch(adminReadingsFilterProvider);
  final repo = ref.watch(supabaseReadingsRepoProvider);

  return repo.search(
    deviceIds: filter.deviceIds.isNotEmpty ? filter.deviceIds : null,
    readingType: 'heat',
    fromDateMs: filter.fromDateMs,
    toDateMs: filter.toDateMs,
    limit: 500,
  );
});

/// All operators for admin filter dropdown.
final allOperatorsProvider =
    FutureProvider.autoDispose<List<SupabaseOperator>>((ref) {
  return ref.watch(supabaseOperatorsRepoProvider).getAll();
});

/// All devices for admin filter chips.
final allDevicesProvider =
    FutureProvider.autoDispose<List<SupabaseDevice>>((ref) {
  return ref.watch(supabaseDevicesRepoProvider).getAll();
});
