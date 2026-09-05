import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../database/supabase_providers.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../data/repositories/supabase_log_sheet_repository.dart';
import '../../data/repositories/supabase_plant_departments_repository.dart';
import '../../data/repositories/supabase_plant_equipments_repository.dart';
import '../../domain/models/log_sheet_entry.dart';
import '../../domain/models/plant_department.dart';
import '../../domain/models/plant_equipment.dart';

// Repositories
final plantDepartmentsRepoProvider = Provider<SupabasePlantDepartmentsRepository>(
  (ref) => SupabasePlantDepartmentsRepository(),
);

final plantEquipmentsRepoProvider = Provider<SupabasePlantEquipmentsRepository>(
  (ref) => SupabasePlantEquipmentsRepository(),
);

// All active plant departments (cached)
final allPlantDepartmentsProvider = FutureProvider<List<PlantDepartment>>((ref) async {
  final repo = ref.watch(plantDepartmentsRepoProvider);
  return repo.getAll(activeOnly: true);
});

// Currently selected department filter in Log Sheets view
final selectedDepartmentIdProvider = StateProvider<String?>((ref) => null);

// Returns departments available to the current logged-in user
// If Admin: returns ALL departments
// If Operator: returns ONLY their allotted departments (or all if none allotted yet)
final userAvailableDepartmentsProvider = FutureProvider<List<PlantDepartment>>((ref) async {
  final allDepts = await ref.watch(allPlantDepartmentsProvider.future);
  final authState = ref.watch(authNotifierProvider);

  if (authState is! AuthAuthenticated) {
    return allDepts;
  }

  final user = authState.user;
  if (user.isAdmin) {
    return allDepts;
  }

  // Operator user: fetch operator record to read allotted_department_ids
  final operatorsRepo = ref.watch(supabaseOperatorsRepoProvider);
  final op = await operatorsRepo.findById(user.id);
  if (op == null || op.allottedDepartmentIds.isEmpty) {
    return allDepts; // Fallback: if not yet allotted, allow all
  }

  final filtered = allDepts.where((d) => op.allottedDepartmentIds.contains(d.id)).toList();
  return filtered.isNotEmpty ? filtered : allDepts;
});

// Equipments for a specific department and optional section
final plantEquipmentsProvider = FutureProvider.autoDispose
    .family<List<PlantEquipment>, ({String? departmentId, String? section})>((ref, args) async {
  final repo = ref.watch(plantEquipmentsRepoProvider);
  return repo.getByDepartment(
    departmentId: args.departmentId,
    section: args.section,
    activeOnly: true,
  );
});

// Main Log Sheets filter query
class LogSheetFilterArgs {
  const LogSheetFilterArgs({
    this.departmentId,
    this.departmentIds,
    this.operatorId,
    this.section,
    this.workType,
    this.fromDateMs,
    this.toDateMs,
  });

  final String? departmentId;
  final List<String>? departmentIds;
  final String? operatorId;
  final String? section;
  final String? workType;
  final int? fromDateMs;
  final int? toDateMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogSheetFilterArgs &&
          runtimeType == other.runtimeType &&
          departmentId == other.departmentId &&
          operatorId == other.operatorId &&
          section == other.section &&
          workType == other.workType &&
          fromDateMs == other.fromDateMs &&
          toDateMs == other.toDateMs;

  @override
  int get hashCode => Object.hash(
        departmentId,
        operatorId,
        section,
        workType,
        fromDateMs,
        toDateMs,
      );
}

final plantLogSheetsListProvider = FutureProvider.autoDispose
    .family<List<LogSheetEntry>, LogSheetFilterArgs>((ref, filter) async {
  final repo = ref.watch(supabaseLogSheetRepoProvider);
  return repo.getAll(
    departmentId: filter.departmentId,
    departmentIds: filter.departmentIds,
    operatorId: filter.operatorId,
    section: filter.section,
    workType: filter.workType,
    fromDateMs: filter.fromDateMs,
    toDateMs: filter.toDateMs,
  );
});
