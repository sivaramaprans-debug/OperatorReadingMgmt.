import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/form_container.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../data/repositories/supabase_log_sheet_repository.dart';
import '../../domain/models/plant_department.dart';
import '../../domain/models/plant_equipment.dart';
import '../notifiers/plant_logsheet_providers.dart';
import '../widgets/equipment_edit_dialog.dart';

class LogSheetAddScreen extends ConsumerStatefulWidget {
  const LogSheetAddScreen({super.key});

  @override
  ConsumerState<LogSheetAddScreen> createState() => _LogSheetAddScreenState();
}

class _LogSheetAddScreenState extends ConsumerState<LogSheetAddScreen> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  String? _selectedDepartmentId;
  String _selectedSection = 'General';
  bool _isCustomSection = false;
  final _customSectionController = TextEditingController();

  String _selectedWorkType = 'Breakdown Repair';
  bool _isCustomWorkType = false;
  final _customWorkTypeController = TextEditingController();

  // Equipment selection
  bool _hasSpecificEquipment = false;
  PlantEquipment? _selectedEquipment;

  final _descriptionController = TextEditingController();

  Uint8List? _pickedImageBytes;
  String? _pickedImageName;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedTime = TimeOfDay.now();
  }

  @override
  void dispose() {
    _customSectionController.dispose();
    _customWorkTypeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }
        if (bytes != null) {
          setState(() {
            _pickedImageBytes = bytes;
            _pickedImageName = file.name;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Failed to pick image: $e');
      }
    }
  }

  void _openAddNewEquipment(List<PlantDepartment> departments) async {
    final result = await EquipmentEditDialog.show(
      context,
      departments: departments,
      initialDepartmentId: _selectedDepartmentId,
      initialSection: _selectedSection,
    );

    if (result != null && mounted) {
      ref.invalidate(plantEquipmentsProvider);
      setState(() {
        _hasSpecificEquipment = true;
        _selectedEquipment = result;
        _selectedDepartmentId = result.departmentId;
        _selectedSection = result.section;
      });
      SnackbarHelper.showSuccess(context, 'Equipment "${result.name}" added and selected');
    }
  }

  Future<void> _onSubmit(List<PlantDepartment> departments) async {
    final desc = _descriptionController.text.trim();
    if (desc.isEmpty) {
      SnackbarHelper.showError(context, 'Please enter a description of the issue/work');
      return;
    }

    final user = ref.read(authNotifierProvider.notifier).currentUser;
    if (user == null) {
      SnackbarHelper.showError(context, 'Not authenticated');
      return;
    }

    final currentDept = departments.where((d) => d.id == _selectedDepartmentId).firstOrNull ??
        (departments.isNotEmpty ? departments.first : null);

    final section = _isCustomSection
        ? _customSectionController.text.trim()
        : _selectedSection;

    final workType = _isCustomWorkType
        ? _customWorkTypeController.text.trim()
        : _selectedWorkType;

    // Combine date & time
    final logDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    ).toUtc().millisecondsSinceEpoch;

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(supabaseLogSheetRepoProvider);

      // Upload image if selected
      String? imageUrl;
      if (_pickedImageBytes != null) {
        imageUrl = await repo.compressAndUploadImage(_pickedImageBytes!);
      }

      final eqName = (_hasSpecificEquipment && _selectedEquipment != null)
          ? _selectedEquipment!.displayName
          : '';

      final eqId = (_hasSpecificEquipment && _selectedEquipment != null)
          ? _selectedEquipment!.id
          : null;

      final snapshot = (_hasSpecificEquipment && _selectedEquipment != null && _selectedEquipment!.nameplateDetails.isNotEmpty)
          ? jsonEncode(_selectedEquipment!.nameplateDetails.map((e) => e.toMap()).toList())
          : null;

      await repo.insert(
        departmentId: currentDept?.id,
        departmentName: currentDept?.name,
        operatorId: user.id,
        operatorName: user.username,
        section: section.isNotEmpty ? section : 'General',
        logDate: logDateTime,
        workType: workType.isNotEmpty ? workType : 'General',
        equipmentId: eqId,
        equipmentType: eqName,
        nameplateSnapshot: snapshot,
        description: desc,
        imageUrl: imageUrl,
      );

      if (!mounted) return;

      ref.invalidate(plantLogSheetsListProvider);
      SnackbarHelper.showSuccess(context, 'Log sheet entry recorded successfully');
      context.pop();
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Failed to save log sheet: $e');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
        title: const Text('New Plant Log Sheet Entry'),
      ),
      body: userDeptsAsync.when(
        loading: () => const LoadingWidget(message: 'Loading plant divisions...'),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (departments) {
          if (departments.isEmpty) {
            return const Center(child: Text('No plant divisions available.'));
          }

          // Initialize selected department if null
          _selectedDepartmentId ??= departments.first.id;
          final currentDept = departments.where((d) => d.id == _selectedDepartmentId).firstOrNull ??
              departments.first;

          // Available sections and work types for this division
          final availableSections = currentDept.sections.isNotEmpty
              ? currentDept.sections
              : ['General Area'];
          if (!_isCustomSection && !availableSections.contains(_selectedSection)) {
            _selectedSection = availableSections.first;
          }

          final availableWorkTypes = currentDept.workTypes.isNotEmpty
              ? currentDept.workTypes
              : ['Breakdown Repair', 'Preventive Maintenance', 'Operation', 'Other'];
          if (!_isCustomWorkType && !availableWorkTypes.contains(_selectedWorkType)) {
            _selectedWorkType = availableWorkTypes.first;
          }

          // Equipments for selected department and section
          final equipmentsAsync = ref.watch(
            plantEquipmentsProvider((
              departmentId: currentDept.id,
              section: _isCustomSection ? null : _selectedSection,
            )),
          );

          final dateStr = DateFormat('EEE, dd MMM yyyy').format(_selectedDate);
          final timeStr = _selectedTime.format(context);

          return FormContainer(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Division / Department
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.business_rounded, color: AppColors.primary, size: 20),
                              const SizedBox(width: 8),
                              Text('Plant Division / Department',
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (departments.length == 1 && !isAdmin) ...[
                            Text(
                              '${departments.first.name} (${departments.first.code})',
                              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ] else ...[
                            DropdownButtonFormField<String>(
                              initialValue: _selectedDepartmentId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              items: departments.map((d) {
                                return DropdownMenuItem(
                                  value: d.id,
                                  child: Text('${d.name} (${d.code})', overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _selectedDepartmentId = v;
                                    _selectedEquipment = null;
                                  });
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Date & Time Selection
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_rounded, size: 18),
                          label: Text(dateStr, style: const TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 1)),
                            );
                            if (picked != null) setState(() => _selectedDate = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time_rounded, size: 18),
                          label: Text(timeStr, style: const TextStyle(fontSize: 13)),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: _selectedTime,
                            );
                            if (picked != null) setState(() => _selectedTime = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 3. Plant Section & Work Type
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Section / Area *', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            if (!_isCustomSection) ...[
                              DropdownButtonFormField<String>(
                                initialValue: availableSections.contains(_selectedSection)
                                    ? _selectedSection
                                    : availableSections.first,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                                items: [
                                  ...availableSections.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))),
                                  const DropdownMenuItem(value: '__custom__', child: Text('+ Custom Section...', style: TextStyle(color: AppColors.primary))),
                                ],
                                onChanged: (v) {
                                  if (v == '__custom__') {
                                    setState(() {
                                      _isCustomSection = true;
                                      _customSectionController.text = '';
                                    });
                                  } else if (v != null) {
                                    setState(() => _selectedSection = v);
                                  }
                                },
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _customSectionController,
                                      decoration: const InputDecoration(
                                        hintText: 'Enter section',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(() => _isCustomSection = false),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Work Type
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Work Type *', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            if (!_isCustomWorkType) ...[
                              DropdownButtonFormField<String>(
                                initialValue: availableWorkTypes.contains(_selectedWorkType)
                                    ? _selectedWorkType
                                    : availableWorkTypes.first,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                                items: [
                                  ...availableWorkTypes.map((wt) => DropdownMenuItem(value: wt, child: Text(wt, overflow: TextOverflow.ellipsis))),
                                  const DropdownMenuItem(value: '__custom__', child: Text('+ Custom Work Type...', style: TextStyle(color: AppColors.primary))),
                                ],
                                onChanged: (v) {
                                  if (v == '__custom__') {
                                    setState(() {
                                      _isCustomWorkType = true;
                                      _customWorkTypeController.text = '';
                                    });
                                  } else if (v != null) {
                                    setState(() => _selectedWorkType = v);
                                  }
                                },
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _customWorkTypeController,
                                      decoration: const InputDecoration(
                                        hintText: 'Enter work type',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(() => _isCustomWorkType = false),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 4. Equipment Selection (Optional Breakdown Toggle!)
                  Card(
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
                              Icon(
                                _hasSpecificEquipment ? Icons.precision_manufacturing_rounded : Icons.report_problem_outlined,
                                color: _hasSpecificEquipment ? AppColors.primary : Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Equipment Selection',
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Switch.adaptive(
                                value: _hasSpecificEquipment,
                                onChanged: (val) {
                                  setState(() {
                                    _hasSpecificEquipment = val;
                                    if (!val) _selectedEquipment = null;
                                  });
                                },
                              ),
                            ],
                          ),
                          Text(
                            _hasSpecificEquipment
                                ? 'Specify the equipment experiencing the issue / maintenance.'
                                : 'General / Line Breakdown (No specific equipment required).',
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                          ),

                          if (_hasSpecificEquipment) ...[
                            const SizedBox(height: 12),
                            equipmentsAsync.when(
                              loading: () => const LinearProgressIndicator(),
                              error: (e, _) => Text('Error loading equipments: $e'),
                              data: (equipments) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<PlantEquipment>(
                                            initialValue: _selectedEquipment,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                              labelText: 'Select Equipment *',
                                              isDense: true,
                                            ),
                                            items: equipments.map((eq) {
                                              return DropdownMenuItem(
                                                value: eq,
                                                child: Text(
                                                  eq.displayName,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (eq) => setState(() => _selectedEquipment = eq),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton.filledTonal(
                                          icon: const Icon(Icons.add_rounded),
                                          tooltip: 'Register New Equipment',
                                          onPressed: () => _openAddNewEquipment(departments),
                                        ),
                                      ],
                                    ),

                                    // Nameplate Preview Card if selected
                                    if (_selectedEquipment != null) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.badge_outlined, size: 16, color: AppColors.primary),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Nameplate Specifications (${_selectedEquipment!.nameplateDetails.length} recorded)',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _selectedEquipment!.nameplateSummary,
                                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 5. Work / Breakdown Description
                  Text('Issue / Work Description *', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Detail the breakdown symptoms, root cause, repairs completed, or observations...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 6. Photo Attachment
                  Text('Attach Photo (Optional)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (_pickedImageBytes != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _pickedImageBytes!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => setState(() {
                                _pickedImageBytes = null;
                                _pickedImageName = null;
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(_pickedImageBytes != null ? 'Change Photo' : 'Add Photo from Device / Camera'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: _pickImage,
                  ),
                  const SizedBox(height: 32),

                  // 7. Submit Button
                  AppButton(
                    label: 'Save Log Sheet Entry',
                    isLoading: _isSubmitting,
                    onPressed: () => _onSubmit(departments),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
