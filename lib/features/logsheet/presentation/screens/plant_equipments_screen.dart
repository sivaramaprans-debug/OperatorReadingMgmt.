import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../domain/models/plant_department.dart';
import '../../domain/models/plant_equipment.dart';
import '../notifiers/plant_logsheet_providers.dart';
import '../widgets/equipment_edit_dialog.dart';

class PlantEquipmentsScreen extends ConsumerStatefulWidget {
  const PlantEquipmentsScreen({
    super.key,
    this.initialDepartmentId,
  });

  final String? initialDepartmentId;

  @override
  ConsumerState<PlantEquipmentsScreen> createState() => _PlantEquipmentsScreenState();
}

class _PlantEquipmentsScreenState extends ConsumerState<PlantEquipmentsScreen> {
  String? _selectedDepartmentId;
  String? _selectedSection;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedDepartmentId = widget.initialDepartmentId;
  }

  void _openAddEditDialog(List<PlantDepartment> depts, [PlantEquipment? equipment]) async {
    final result = await EquipmentEditDialog.show(
      context,
      equipment: equipment,
      departments: depts,
      initialDepartmentId: _selectedDepartmentId,
      initialSection: _selectedSection,
    );

    if (result != null && mounted) {
      ref.invalidate(plantEquipmentsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(equipment == null
              ? 'Equipment "${result.name}" created'
              : 'Equipment "${result.name}" updated'),
        ),
      );
    }
  }

  Future<void> _confirmDelete(PlantEquipment eq) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Equipment'),
        content: Text('Are you sure you want to deactivate "${eq.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      await ref.read(plantEquipmentsRepoProvider).delete(eq.id);
      ref.invalidate(plantEquipmentsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userDeptsAsync = ref.watch(userAvailableDepartmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Equipments & Specs'),
      ),
      body: userDeptsAsync.when(
        loading: () => const LoadingWidget(message: 'Loading divisions...'),
        error: (e, _) => Center(child: Text('Error loading divisions: $e')),
        data: (departments) {
          if (departments.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.business_outlined,
              title: 'No Divisions Found',
              subtitle: 'Please create a plant department first.',
            );
          }

          // Default selected department if not set
          _selectedDepartmentId ??= departments.first.id;
          final currentDept = departments.where((d) => d.id == _selectedDepartmentId).firstOrNull ??
              departments.first;

          final eqAsync = ref.watch(
            plantEquipmentsProvider((
              departmentId: currentDept.id,
              section: _selectedSection,
            )),
          );

          return Column(
            children: [
              // Department Switcher Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                child: Column(
                  children: [
                    // Division Selector
                    Row(
                      children: [
                        const Icon(Icons.business_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        const Text('Division: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedDepartmentId,
                            underline: const SizedBox(),
                            items: departments.map((d) {
                              return DropdownMenuItem(
                                value: d.id,
                                child: Text(
                                  '${d.name} (${d.code})',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _selectedDepartmentId = v;
                                  _selectedSection = null;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    // Section Filter Chips (if sections configured)
                    if (currentDept.sections.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('All Sections'),
                              selected: _selectedSection == null || _selectedSection == 'All',
                              onSelected: (_) => setState(() => _selectedSection = null),
                            ),
                            const SizedBox(width: 6),
                            ...currentDept.sections.map((sec) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(sec),
                                  selected: _selectedSection == sec,
                                  onSelected: (sel) => setState(() => _selectedSection = sel ? sec : null),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),
                    // Search bar
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search equipment name, tag, make...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    ),
                  ],
                ),
              ),

              // Equipment List
              Expanded(
                child: eqAsync.when(
                  loading: () => const LoadingWidget(message: 'Loading equipments...'),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (equipments) {
                    var filtered = equipments;
                    if (_searchQuery.isNotEmpty) {
                      filtered = filtered.where((e) {
                        final inName = e.name.toLowerCase().contains(_searchQuery);
                        final inTag = e.equipmentTag.toLowerCase().contains(_searchQuery);
                        final inSpecs = e.nameplateDetails.any(
                          (f) => f.key.toLowerCase().contains(_searchQuery) || f.value.toLowerCase().contains(_searchQuery),
                        );
                        return inName || inTag || inSpecs;
                      }).toList();
                    }

                    if (filtered.isEmpty) {
                      return EmptyStateWidget(
                        icon: Icons.precision_manufacturing_outlined,
                        title: 'No Equipments Registered',
                        subtitle: 'Tap the button below to register equipment with custom nameplate details.',
                        actionLabel: 'Add Equipment',
                        action: () => _openAddEditDialog(departments),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final eq = filtered[index];
                        return _EquipmentCard(
                          equipment: eq,
                          onEdit: () => _openAddEditDialog(departments, eq),
                          onDelete: () => _confirmDelete(eq),
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
      floatingActionButton: userDeptsAsync.hasValue && userDeptsAsync.value!.isNotEmpty
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Equipment'),
              onPressed: () => _openAddEditDialog(userDeptsAsync.value!),
            )
          : null,
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({
    required this.equipment,
    required this.onEdit,
    required this.onDelete,
  });

  final PlantEquipment equipment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: const Icon(Icons.precision_manufacturing_rounded, color: AppColors.primary, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                equipment.name,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (equipment.equipmentTag.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  equipment.equipmentTag,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.layers_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                equipment.section,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Icon(Icons.badge_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${equipment.nameplateDetails.length} Specs',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'NAMEPLATE SPECIFICATIONS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: AppColors.primary,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Edit Equipment & Specs',
                          onPressed: onEdit,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          tooltip: 'Deactivate Equipment',
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (equipment.nameplateDetails.isEmpty)
                  Text(
                    'No nameplate details registered. Tap edit to add specifications.',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: equipment.nameplateDetails.map((field) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodySmall,
                            children: [
                              TextSpan(
                                text: '${field.key}: ',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                              TextSpan(
                                text: field.value.isNotEmpty ? field.value : '—',
                                style: TextStyle(color: theme.colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
