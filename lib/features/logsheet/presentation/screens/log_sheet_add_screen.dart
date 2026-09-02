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
import '../../../../shared/widgets/snackbar_helper.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../data/repositories/supabase_log_sheet_repository.dart';

class LogSheetAddScreen extends ConsumerStatefulWidget {
  const LogSheetAddScreen({super.key});

  @override
  ConsumerState<LogSheetAddScreen> createState() => _LogSheetAddScreenState();
}

class _LogSheetAddScreenState extends ConsumerState<LogSheetAddScreen> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  String _selectedSection = 'Furnace / Induction';
  String _selectedWorkType = 'Maintenance';
  final _equipmentController = TextEditingController();
  final _descriptionController = TextEditingController();

  Uint8List? _pickedImageBytes;
  String? _pickedImageName;
  bool _isSubmitting = false;
  List<String> _equipmentSuggestions = [];

  static const List<String> _sections = [
    'Furnace / Induction',
    'CCM',
    'Rolling Mill',
    'Dedusting / Pollution',
    'Water Treatment',
    'Electrical Substation',
    'Utility / Compressor',
    'General Plant',
  ];

  static const List<String> _workTypes = [
    'Maintenance',
    'Electrical',
    'Mechanical',
    'Operation',
    'Inspection',
    'Breakdown Repair',
    'Cleaning / Routine',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedTime = TimeOfDay.now();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final list = await ref
        .read(supabaseLogSheetRepoProvider)
        .getEquipmentSuggestions(_selectedSection);
    if (mounted) {
      setState(() => _equipmentSuggestions = list);
    }
  }

  @override
  void dispose() {
    _equipmentController.dispose();
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
        SnackbarHelper.showError(context, 'Could not select image: $e');
      }
    }
  }

  Future<void> _onSubmit() async {
    final user = ref.read(authNotifierProvider.notifier).currentUser;
    if (user == null) return;

    final equipment = _equipmentController.text.trim();
    final description = _descriptionController.text.trim();

    if (equipment.isEmpty) {
      SnackbarHelper.showError(context, 'Please enter or select the equipment type.');
      return;
    }

    if (description.isEmpty) {
      SnackbarHelper.showError(context, 'Please enter the work description.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(supabaseLogSheetRepoProvider);

      String? imageUrl;
      if (_pickedImageBytes != null) {
        // Compress down to ~100 KB and upload to Supabase free storage
        imageUrl = await repo.compressAndUploadImage(_pickedImageBytes!);
      }

      final logDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      await repo.insert(
        operatorId: user.id,
        operatorName: user.username,
        section: _selectedSection,
        logDate: logDateTime.toUtc().millisecondsSinceEpoch,
        workType: _selectedWorkType,
        equipmentType: equipment,
        description: description,
        imageUrl: imageUrl,
      );

      if (mounted) {
        ref.invalidate(logSheetsListProvider);
        SnackbarHelper.showSuccess(context, 'Log Sheet entry recorded successfully!');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Failed to save log entry: $e');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Log Sheet Entry'),
      ),
      body: FormContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date & Time Picker
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_rounded),
                      title: const Text('Date', style: TextStyle(fontSize: 12)),
                      subtitle: Text(DateFormat('dd MMM yyyy').format(_selectedDate),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2101),
                        );
                        if (picked != null) setState(() => _selectedDate = picked);
                      },
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time_rounded),
                      title: const Text('Time', style: TextStyle(fontSize: 12)),
                      subtitle: Text(_selectedTime.format(context),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () async {
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
              const Divider(height: 24),

              // Section Dropdown
              DropdownButtonFormField<String>(
                value: _selectedSection,
                decoration: const InputDecoration(
                  labelText: 'Section / Area',
                  prefixIcon: Icon(Icons.apartment_rounded),
                ),
                items: _sections
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedSection = val);
                    _loadSuggestions();
                  }
                },
              ),
              const SizedBox(height: 16),

              // Work Type Selector
              Text('Type of Work', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _workTypes.map((type) {
                  final isSelected = _selectedWorkType == type;
                  return ChoiceChip(
                    label: Text(type, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    selected: isSelected,
                    selectedColor: AppColors.primaryContainer,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedWorkType = type);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Equipment Type with Autocomplete
              Text('Equipment Type', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return _equipmentSuggestions;
                  }
                  return _equipmentSuggestions.where((option) =>
                      option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (selection) {
                  _equipmentController.text = selection;
                },
                fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                  // Connect internal controller with ours
                  textEditingController.addListener(() {
                    _equipmentController.text = textEditingController.text;
                  });
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'e.g. Induction Coil #2, Blower Motor, Pump #1',
                      prefixIcon: const Icon(Icons.precision_manufacturing_rounded),
                      helperText: 'Select existing or type a new equipment name',
                    ),
                    textInputAction: TextInputAction.next,
                  );
                },
              ),
              const SizedBox(height: 20),

              // Description
              Text('Work Description / Observations', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              TextField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: 'Describe maintenance done, parameters checked, faults observed, or parts replaced...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),

              // Photo Attachment Section
              Text('Photo Attachment (Optional)', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_pickedImageBytes == null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo_rounded),
                  label: const Text('Select / Capture Photo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _pickImage,
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _pickedImageBytes!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pickedImageName ?? 'Attached Photo',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'Auto-compressed to ~100 KB for fast loading',
                              style: TextStyle(fontSize: 11, color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                        tooltip: 'Remove photo',
                        onPressed: () {
                          setState(() {
                            _pickedImageBytes = null;
                            _pickedImageName = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 32),

              // Submit Button
              AppButton(
                label: 'Save Log Sheet Entry',
                isLoading: _isSubmitting,
                onPressed: _onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
