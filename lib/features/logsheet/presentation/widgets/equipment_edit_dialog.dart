import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/plant_department.dart';
import '../../domain/models/plant_equipment.dart';
import '../notifiers/plant_logsheet_providers.dart';

class EquipmentEditDialog extends ConsumerStatefulWidget {
  const EquipmentEditDialog({
    super.key,
    this.equipment,
    required this.departments,
    this.initialDepartmentId,
    this.initialSection,
  });

  final PlantEquipment? equipment;
  final List<PlantDepartment> departments;
  final String? initialDepartmentId;
  final String? initialSection;

  static Future<PlantEquipment?> show(
    BuildContext context, {
    PlantEquipment? equipment,
    required List<PlantDepartment> departments,
    String? initialDepartmentId,
    String? initialSection,
  }) {
    return showDialog<PlantEquipment>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EquipmentEditDialog(
        equipment: equipment,
        departments: departments,
        initialDepartmentId: initialDepartmentId,
        initialSection: initialSection,
      ),
    );
  }

  @override
  ConsumerState<EquipmentEditDialog> createState() => _EquipmentEditDialogState();
}

class _EquipmentEditDialogState extends ConsumerState<EquipmentEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _tagController;
  late TextEditingController _sectionController;
  late String _selectedDepartmentId;
  late List<NameplateField> _nameplateFields;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final eq = widget.equipment;
    _nameController = TextEditingController(text: eq?.name ?? '');
    _tagController = TextEditingController(text: eq?.equipmentTag ?? '');
    _sectionController = TextEditingController(text: eq?.section ?? widget.initialSection ?? 'General');

    if (eq != null) {
      _selectedDepartmentId = eq.departmentId;
      _nameplateFields = eq.nameplateDetails.map((f) => f.copy()).toList();
    } else {
      _selectedDepartmentId = widget.initialDepartmentId ??
          (widget.departments.isNotEmpty ? widget.departments.first.id : '');
      _nameplateFields = [
        NameplateField(key: 'Make', value: ''),
        NameplateField(key: 'Power', value: ''),
        NameplateField(key: 'RPM', value: ''),
        NameplateField(key: 'Voltage', value: ''),
      ];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  PlantDepartment? get _currentDepartment {
    return widget.departments.where((d) => d.id == _selectedDepartmentId).firstOrNull;
  }

  void _addField() {
    setState(() {
      _nameplateFields.add(NameplateField(key: '', value: ''));
    });
  }

  void _removeField(int index) {
    setState(() {
      _nameplateFields.removeAt(index);
    });
  }

  void _addCommonMotorSpecs() {
    final defaultKeys = ['Make', 'Power (kW)', 'RPM', 'Voltage', 'Current (A)', 'Frame', 'DE Bearing', 'NDE Bearing'];
    setState(() {
      for (final k in defaultKeys) {
        if (!_nameplateFields.any((f) => f.key.toLowerCase() == k.toLowerCase())) {
          _nameplateFields.add(NameplateField(key: k, value: ''));
        }
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final dept = _currentDepartment;
    if (dept == null) return;

    setState(() => _isSaving = true);
    final repo = ref.read(plantEquipmentsRepoProvider);

    try {
      final cleanFields = _nameplateFields
          .where((f) => f.key.trim().isNotEmpty)
          .map((f) => NameplateField(key: f.key.trim(), value: f.value.trim()))
          .toList();

      if (widget.equipment != null) {
        await repo.update(
          widget.equipment!.id,
          name: _nameController.text.trim(),
          equipmentTag: _tagController.text.trim(),
          section: _sectionController.text.trim(),
          nameplateDetails: cleanFields,
        );
        final updated = widget.equipment!.copyWith(
          name: _nameController.text.trim(),
          equipmentTag: _tagController.text.trim(),
          section: _sectionController.text.trim(),
          nameplateDetails: cleanFields,
        );
        if (mounted) Navigator.pop(context, updated);
      } else {
        final id = await repo.create(
          departmentId: dept.id,
          departmentName: dept.name,
          section: _sectionController.text.trim(),
          name: _nameController.text.trim(),
          equipmentTag: _tagController.text.trim(),
          nameplateDetails: cleanFields,
          createdBy: 'user',
        );
        final created = PlantEquipment(
          id: id,
          departmentId: dept.id,
          departmentName: dept.name,
          section: _sectionController.text.trim(),
          name: _nameController.text.trim(),
          equipmentTag: _tagController.text.trim(),
          nameplateDetails: cleanFields,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        if (mounted) Navigator.pop(context, created);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving equipment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.equipment != null;
    final dept = _currentDepartment;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: const Icon(Icons.precision_manufacturing_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit Equipment & Nameplate' : 'Add Equipment',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Nameplate fields and values are fully customizable',
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Content scrollable
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Department selector (if not editing or if admin)
                        DropdownButtonFormField<String>(
                          initialValue: _selectedDepartmentId.isNotEmpty ? _selectedDepartmentId : null,
                          decoration: const InputDecoration(
                            labelText: 'Plant Department / Division *',
                            prefixIcon: Icon(Icons.business_rounded),
                          ),
                          items: widget.departments.map((d) {
                            return DropdownMenuItem(
                              value: d.id,
                              child: Text('${d.name} (${d.code})'),
                            );
                          }).toList(),
                          onChanged: isEditing
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setState(() {
                                      _selectedDepartmentId = v;
                                      final newDept = widget.departments.where((d) => d.id == v).firstOrNull;
                                      if (newDept != null && newDept.sections.isNotEmpty) {
                                        _sectionController.text = newDept.sections.first;
                                      }
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 14),

                        // Section dropdown or text
                        if (dept != null && dept.sections.isNotEmpty) ...[
                          DropdownButtonFormField<String>(
                            initialValue: dept.sections.contains(_sectionController.text)
                                ? _sectionController.text
                                : dept.sections.first,
                            decoration: const InputDecoration(
                              labelText: 'Plant Area / Section',
                              prefixIcon: Icon(Icons.layers_outlined),
                            ),
                            items: dept.sections.map((s) {
                              return DropdownMenuItem(value: s, child: Text(s));
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _sectionController.text = v);
                            },
                          ),
                        ] else ...[
                          TextFormField(
                            controller: _sectionController,
                            decoration: const InputDecoration(
                              labelText: 'Plant Area / Section',
                              prefixIcon: Icon(Icons.layers_outlined),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // Equipment Name
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Equipment Name *',
                            hintText: 'e.g. Kiln Main Drive Motor, ID Fan, Furnace TR',
                            prefixIcon: Icon(Icons.settings_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter equipment name' : null,
                        ),
                        const SizedBox(height: 14),

                        // Equipment Tag / Code
                        TextFormField(
                          controller: _tagController,
                          decoration: const InputDecoration(
                            labelText: 'Equipment Tag / Serial No. (Optional)',
                            hintText: 'e.g. MTR-KILN-01, TR-01',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Nameplate Details Header
                        Row(
                          children: [
                            const Icon(Icons.badge_outlined, size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Nameplate Details (Editable Fields)',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('Add Motor Specs', style: TextStyle(fontSize: 12)),
                              onPressed: _addCommonMotorSpecs,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // List of dynamic nameplate attributes
                        if (_nameplateFields.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Text('No nameplate fields yet. Tap "+ Add Field" below to add custom specs.'),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _nameplateFields.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final field = _nameplateFields[index];
                              return Row(
                                children: [
                                  // Field Name / Key (Editable!)
                                  Expanded(
                                    flex: 4,
                                    child: TextFormField(
                                      initialValue: field.key,
                                      decoration: InputDecoration(
                                        hintText: 'Field Name (e.g. RPM)',
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (v) => field.key = v,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Field Value (Editable!)
                                  Expanded(
                                    flex: 5,
                                    child: TextFormField(
                                      initialValue: field.value,
                                      decoration: InputDecoration(
                                        hintText: 'Value (e.g. 1480)',
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (v) => field.value = v,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                    tooltip: 'Delete field',
                                    onPressed: () => _removeField(index),
                                  ),
                                ],
                              );
                            },
                          ),

                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add Custom Specification Field'),
                          onPressed: _addField,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 24),
                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(isEditing ? 'Save Changes' : 'Create Equipment'),
                      onPressed: _isSaving ? null : _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
