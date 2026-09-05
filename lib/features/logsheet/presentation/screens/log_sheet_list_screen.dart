import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../data/repositories/supabase_log_sheet_repository.dart';
import '../../domain/models/log_sheet_entry.dart';
import '../../domain/models/plant_department.dart';
import '../notifiers/plant_logsheet_providers.dart';
import '../widgets/interactive_image_viewer.dart';

class LogSheetListScreen extends ConsumerStatefulWidget {
  const LogSheetListScreen({super.key});

  @override
  ConsumerState<LogSheetListScreen> createState() => _LogSheetListScreenState();
}

class _LogSheetListScreenState extends ConsumerState<LogSheetListScreen> {
  String? _selectedDepartmentId;
  String _selectedSection = 'All';
  String _selectedWorkType = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  final List<String> _sections = ['All'];
  final List<String> _workTypes = [
    'All',
    'Breakdown Repair',
    'Preventive Maintenance',
    'Inspection',
    'Cleaning / Routine',
    'Electrical',
    'Mechanical',
    'Operation',
    'Other',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _syncDepartmentOptions(PlantDepartment? dept) {
    if (dept != null && dept.sections.isNotEmpty) {
      for (final s in dept.sections) {
        if (!_sections.contains(s)) _sections.add(s);
      }
      for (final wt in dept.workTypes) {
        if (!_workTypes.contains(wt)) _workTypes.add(wt);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authNotifierProvider.notifier).currentUser;
    final isAdmin = user?.role == 'admin';

    final userDeptsAsync = ref.watch(userAvailableDepartmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Plant Log Sheets (All Divisions)' : 'Division Log Sheets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.precision_manufacturing_outlined),
            tooltip: 'Equipments & Nameplates',
            onPressed: () => context.push(RoutePaths.plantEquipments),
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.apartment_rounded),
              tooltip: 'Manage Departments',
              onPressed: () => context.push(RoutePaths.adminDepartments),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(plantLogSheetsListProvider);
              ref.invalidate(userAvailableDepartmentsProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.logSheetAdd),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Log Entry'),
      ),
      body: userDeptsAsync.when(
        loading: () => const LoadingWidget(message: 'Loading plant divisions...'),
        error: (e, _) => Center(child: Text('Error loading divisions: $e')),
        data: (departments) {
          // If operator has only 1 division, lock to that division
          if (!isAdmin && departments.isNotEmpty && _selectedDepartmentId == null) {
            _selectedDepartmentId = departments.first.id;
          }

          final currentDept = departments.where((d) => d.id == _selectedDepartmentId).firstOrNull;
          _syncDepartmentOptions(currentDept);

          final filterArgs = LogSheetFilterArgs(
            departmentId: _selectedDepartmentId,
            departmentIds: (!isAdmin && _selectedDepartmentId == null && departments.isNotEmpty)
                ? departments.map((d) => d.id).toList()
                : null,
            section: _selectedSection == 'All' ? null : _selectedSection,
            workType: _selectedWorkType == 'All' ? null : _selectedWorkType,
          );

          final logsAsync = ref.watch(plantLogSheetsListProvider(filterArgs));

          return Column(
            children: [
              // Top Filter Bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                child: Column(
                  children: [
                    // Department Selector
                    Row(
                      children: [
                        const Icon(Icons.business_rounded, size: 20, color: AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Division: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: DropdownButton<String?>(
                            isExpanded: true,
                            value: _selectedDepartmentId,
                            underline: const SizedBox(),
                            items: [
                              if (isAdmin)
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All Divisions (Whole Plant)', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ...departments.map((d) {
                                return DropdownMenuItem<String?>(
                                  value: d.id,
                                  child: Text(
                                    '${d.name} (${d.code})',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedDepartmentId = val;
                                _selectedSection = 'All';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Search Input
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search equipment, issue description, operator...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 10),

                    // Section & Work Type Filters
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedSection,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Section',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            items: _sections
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedSection = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedWorkType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Work Type',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            items: _workTypes
                                .map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedWorkType = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Log List
              Expanded(
                child: logsAsync.when(
                  loading: () => const LoadingWidget(message: 'Loading log sheets...'),
                  error: (e, _) {
                    return EmptyStateWidget(
                      icon: Icons.table_chart_outlined,
                      title: 'Unable to Load Logs',
                      subtitle: 'Error: $e',
                      actionLabel: 'Try Again',
                      action: () => ref.invalidate(plantLogSheetsListProvider),
                    );
                  },
                  data: (logs) {
                    var filtered = logs;
                    if (_searchQuery.isNotEmpty) {
                      filtered = filtered.where((l) =>
                          l.equipmentType.toLowerCase().contains(_searchQuery) ||
                          l.description.toLowerCase().contains(_searchQuery) ||
                          l.operatorName.toLowerCase().contains(_searchQuery) ||
                          l.section.toLowerCase().contains(_searchQuery) ||
                          l.workType.toLowerCase().contains(_searchQuery) ||
                          (l.departmentName ?? '').toLowerCase().contains(_searchQuery)).toList();
                    }

                    if (filtered.isEmpty) {
                      return EmptyStateWidget(
                        icon: Icons.article_outlined,
                        title: 'No Log Entries Found',
                        subtitle: 'Tap the button below to add your first plant log sheet or breakdown entry.',
                        actionLabel: 'Add Log Entry',
                        action: () => context.push(RoutePaths.logSheetAdd),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length + 1, // extra padding for FAB
                      itemBuilder: (context, index) {
                        if (index == filtered.length) {
                          return const SizedBox(height: 72);
                        }
                        final entry = filtered[index];
                        return _LogSheetCard(
                          entry: entry,
                          canDelete: isAdmin || entry.operatorId == user?.id,
                          onDelete: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Log Entry'),
                                content: const Text('Are you sure you want to delete this log sheet record?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ref.read(supabaseLogSheetRepoProvider).delete(entry.id);
                              ref.invalidate(plantLogSheetsListProvider);
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LogSheetCard extends StatelessWidget {
  const _LogSheetCard({
    required this.entry,
    required this.canDelete,
    required this.onDelete,
  });

  final LogSheetEntry entry;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logDate = DateTime.fromMillisecondsSinceEpoch(entry.logDate, isUtc: true).toLocal();
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(logDate);
    final isBreakdown = entry.workType.toLowerCase().contains('breakdown');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isBreakdown ? Colors.red.shade200 : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isBreakdown ? 1.5 : 1,
        ),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Department & Section & Work Type Chips + Delete
            Row(
              children: [
                if (entry.departmentName != null && entry.departmentName!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.departmentName!,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.section,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isBreakdown ? Colors.red.shade50 : theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.workType,
                    style: TextStyle(
                      color: isBreakdown ? Colors.red.shade800 : theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  dateStr,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                ),
                if (canDelete) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Equipment or General Breakdown Indicator
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  entry.hasEquipment ? Icons.precision_manufacturing_rounded : Icons.report_problem_outlined,
                  size: 20,
                  color: entry.hasEquipment ? AppColors.primary : (isBreakdown ? Colors.red : Colors.orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.hasEquipment ? entry.equipmentType : 'General / Plant Line Breakdown (No specific equipment)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: entry.hasEquipment ? null : (isBreakdown ? Colors.red.shade800 : Colors.orange.shade900),
                    ),
                  ),
                ),
              ],
            ),

            // Nameplate Snapshot (if saved with equipment)
            if (entry.nameplateSnapshot != null && entry.nameplateSnapshot!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _NameplateSnapshotView(rawSnapshot: entry.nameplateSnapshot!),
            ],

            const SizedBox(height: 10),

            // Description
            Text(
              entry.description,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 12),

            // Attached Photo with Pinch-to-Zoom Viewer
            if (entry.imageUrl != null && entry.imageUrl!.isNotEmpty) ...[
              GestureDetector(
                onTap: () {
                  InteractiveImageViewer.show(
                    context,
                    imageUrl: entry.imageUrl!,
                    title: entry.hasEquipment ? entry.equipmentType : 'General Breakdown',
                    subtitle: '${entry.section} • $dateStr',
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          entry.imageUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_not_supported_rounded, color: Colors.grey),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.zoom_in_rounded, size: 16, color: AppColors.primary),
                                SizedBox(width: 4),
                                Text(
                                  'Tap for 2-Finger Zoom',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pinch with two fingers or double-tap to zoom up to 5x',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Operator Footer
            Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Logged by: ${entry.operatorName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NameplateSnapshotView extends StatelessWidget {
  const _NameplateSnapshotView({required this.rawSnapshot});
  final String rawSnapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    try {
      final decoded = jsonDecode(rawSnapshot);
      if (decoded is List) {
        final specs = decoded.whereType<Map>().map((m) => '${m['key']}: ${m['value']}').take(5).join(' • ');
        if (specs.isEmpty) return const SizedBox();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Specs: $specs',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
    } catch (_) {}
    return const SizedBox();
  }
}
