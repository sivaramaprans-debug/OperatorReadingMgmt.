import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../domain/models/plant_department.dart';
import '../notifiers/plant_logsheet_providers.dart';

class AdminDepartmentsScreen extends ConsumerStatefulWidget {
  const AdminDepartmentsScreen({super.key});

  @override
  ConsumerState<AdminDepartmentsScreen> createState() => _AdminDepartmentsScreenState();
}

class _AdminDepartmentsScreenState extends ConsumerState<AdminDepartmentsScreen> {
  void _openDepartmentDialog([PlantDepartment? dept]) async {
    final isEditing = dept != null;
    final nameCtrl = TextEditingController(text: dept?.name ?? '');
    final codeCtrl = TextEditingController(text: dept?.code ?? '');
    final descCtrl = TextEditingController(text: dept?.description ?? '');
    final sections = List<String>.from(dept?.sections ?? ['General']);
    final workTypes = List<String>.from(dept?.workTypes ?? [
      'Breakdown Repair',
      'Preventive Maintenance',
      'Inspection',
      'Cleaning / Routine',
      'Electrical',
      'Mechanical',
      'Operation',
      'Other',
    ]);

    final newSectionCtrl = TextEditingController();
    final newWorkTypeCtrl = TextEditingController();

    Future<void> onSave(BuildContext ctx) async {
      final name = nameCtrl.text.trim();
      final code = codeCtrl.text.trim();
      if (name.isEmpty || code.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name and Code are required')),
        );
        return;
      }

      final repo = ref.read(plantDepartmentsRepoProvider);
      if (isEditing) {
        await repo.update(
          dept.id,
          name: name,
          code: code,
          description: descCtrl.text.trim(),
          sections: sections,
          workTypes: workTypes,
        );
      } else {
        await repo.create(
          name: name,
          code: code,
          description: descCtrl.text.trim(),
          sections: sections,
          workTypes: workTypes,
        );
      }
      if (ctx.mounted) Navigator.pop(ctx, true);
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final screenHeight = MediaQuery.of(context).size.height;
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 540, maxHeight: screenHeight * 0.85),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                          child: const Icon(Icons.business_rounded, color: AppColors.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isEditing ? 'Edit Division' : 'Add Division',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Save'),
                          onPressed: () => onSave(ctx),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cancel',
                          onPressed: () => Navigator.pop(ctx, false),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Department / Division Name *',
                                hintText: 'e.g. Sponge Iron Division, SMS 2, CPP',
                                prefixIcon: Icon(Icons.apartment_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: codeCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Division Code *',
                                hintText: 'e.g. SID, SMS 2, CPP, RM',
                                prefixIcon: Icon(Icons.tag_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: descCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Description (Optional)',
                                hintText: 'Brief summary of plant area...',
                                prefixIcon: Icon(Icons.info_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Sections list
                            Text('Plant Sections / Areas', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: sections.map((s) {
                                return Chip(
                                  label: Text(s),
                                  onDeleted: () {
                                    setDialogState(() => sections.remove(s));
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: newSectionCtrl,
                                    decoration: const InputDecoration(
                                      hintText: 'Add section (e.g. Kiln, Cooler, ESP)',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.add),
                                  onPressed: () {
                                    final text = newSectionCtrl.text.trim();
                                    if (text.isNotEmpty && !sections.contains(text)) {
                                      setDialogState(() {
                                        sections.add(text);
                                        newSectionCtrl.clear();
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),
                            // Work Types list
                            Text('Allowed Work Types', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: workTypes.map((wt) {
                                return Chip(
                                  label: Text(wt),
                                  onDeleted: () {
                                    setDialogState(() => workTypes.remove(wt));
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: newWorkTypeCtrl,
                                    decoration: const InputDecoration(
                                      hintText: 'Add work type (e.g. Electrical, Routine)',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.add),
                                  onPressed: () {
                                    final text = newWorkTypeCtrl.text.trim();
                                    if (text.isNotEmpty && !workTypes.contains(text)) {
                                      setDialogState(() {
                                        workTypes.add(text);
                                        newWorkTypeCtrl.clear();
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.check_rounded),
                            label: Text(isEditing ? 'Save Changes' : 'Create Division'),
                            onPressed: () => onSave(ctx),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (saved == true && mounted) {
      ref.invalidate(allPlantDepartmentsProvider);
      ref.invalidate(userAvailableDepartmentsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEditing ? 'Department updated' : 'Department created')),
      );
    }
  }

  Future<void> _confirmDelete(PlantDepartment dept) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Department'),
        content: Text('Are you sure you want to deactivate "${dept.name} (${dept.code})"?'),
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
      await ref.read(plantDepartmentsRepoProvider).delete(dept.id);
      ref.invalidate(allPlantDepartmentsProvider);
      ref.invalidate(userAvailableDepartmentsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deptsAsync = ref.watch(allPlantDepartmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Plant Departments'),
      ),
      body: deptsAsync.when(
        loading: () => const LoadingWidget(message: 'Loading departments...'),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (departments) {
          if (departments.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.business_outlined,
              title: 'No Departments Found',
              subtitle: 'Create divisions like Sponge Iron (SID), SMS 2, SMS 3, SMS 4, CPP, etc.',
              actionLabel: 'Add Department',
              action: () => _openDepartmentDialog(),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: departments.length,
            itemBuilder: (context, index) {
              final d = departments[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                            child: Text(
                              d.code.length > 3 ? d.code.substring(0, 3) : d.code,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                if (d.description.isNotEmpty)
                                  Text(
                                    d.description,
                                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit Department',
                            onPressed: () => _openDepartmentDialog(d),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Deactivate Department',
                            onPressed: () => _confirmDelete(d),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: d.sections.map((sec) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(sec, style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Add Department'),
        onPressed: () => _openDepartmentDialog(),
      ),
    );
  }
}
