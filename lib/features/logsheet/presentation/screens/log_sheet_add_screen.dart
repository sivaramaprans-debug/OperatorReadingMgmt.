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
  bool _isCustomSection = false;
  final _customSectionController = TextEditingController();

  String _selectedWorkType = 'Operation';
  final List<String> _availableWorkTypes = [
    'Operation',
    'Inspection',
    'Breakdown Repair',
    'Cleaning / Routine',
    'Maintenance',
    'Electrical',
    'Mechanical',
    'Other',
  ];

  final List<String> _availableSections = [
    'Furnace / Induction',
    'CCM',
    'Rolling Mill',
    'Dedusting / Pollution',
    'Water Treatment',
    'Electrical Substation',
    'Utility / Compressor',
    'General Plant',
  ];

  final _equipmentController = TextEditingController();
  final _descriptionController = TextEditingController();

  Uint8List? _pickedImageBytes;
  String? _pickedImageName;
  bool _isSubmitting = false;
  List<String> _equipmentSuggestions = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedTime = TimeOfDay.now();
    _loadAllSuggestions();
  }

  Future<void> _loadAllSuggestions() async {
    try {
      final repo = ref.read(supabaseLogSheetRepoProvider);
      final eqList = await repo.getEquipmentSuggestions(_effectiveSection);
      final secList = await repo.getSectionSuggestions();
      final wtList = await repo.getWorkTypeSuggestions();

      if (mounted) {
        setState(() {
          _equipmentSuggestions = eqList;
          for (final s in secList) {
            if (!_availableSections.contains(s)) {
              _availableSections.add(s);
            }
          }
          for (final wt in wtList) {
            if (!_availableWorkTypes.contains(wt)) {
              _availableWorkTypes.add(wt);
            }
          }
        });
      }
    } catch (_) {}
  }

  String get _effectiveSection {
    if (_isCustomSection) {
      return _customSectionController.text.trim();
    }
    return _selectedSection;
  }

  @override
  void dispose() {
    _customSectionController.dispose();
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

  void _promptAddCustomWorkType() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Custom Work Type'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Refractory Relining, Calibration',
            labelText: 'Work Type Name',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = textController.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  if (!_availableWorkTypes.contains(text)) {
                    _availableWorkTypes.insert(_availableWorkTypes.length - 1, text);
                  }
                  _selectedWorkType = text;
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add & Select'),
          ),
        ],
      ),
    );
  }

  void _promptAddCustomSection() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Custom Section / Area'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. SMS4 Refractory, Yard',
            labelText: 'Section Name',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = textController.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  if (!_availableSections.contains(text)) {
                    _availableSections.add(text);
                  }
                  _selectedSection = text;
                  _isCustomSection = false;
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add & Select'),
          ),
        ],
      ),
    );
  }

  Future<void> _onSubmit() async {
    final user = ref.read(authNotifierProvider.notifier).currentUser;
    if (user == null) return;

    final section = _effectiveSection;
    final equipment = _equipmentController.text.trim();
    final description = _descriptionController.text.trim();

    if (section.isEmpty) {
      SnackbarHelper.showError(context, 'Please specify the section or plant area.');
      return;
    }

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
        section: section,
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
        final errorStr = e.toString();
        if (errorStr.contains('PGRST205') || errorStr.contains('schema cache') || errorStr.contains('not find the table')) {
          _showDatabaseSetupDialog();
        } else {
          SnackbarHelper.showError(context, 'Failed to save log entry: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showDatabaseSetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Database Setup Required'),
          ],
        ),
        content: const Text(
          'The log_sheets table has not been initialized in Supabase yet.\n\n'
          'Please execute the provided SQL setup script once in your Supabase SQL Editor to enable Work Logs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

              // Section Dropdown with Add Custom Section Option
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Section / Plant Area', style: theme.textTheme.titleSmall),
                  TextButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('+ Add Custom Section', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _promptAddCustomSection,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _availableSections.contains(_selectedSection) ? _selectedSection : _availableSections.first,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select Section',
                  prefixIcon: Icon(Icons.apartment_rounded),
                ),
                items: [
                  ..._availableSections.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                  const DropdownMenuItem(
                    value: '__custom__',
                    child: Text('✏️ Type Custom Section...', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                ],
                onChanged: (val) {
                  if (val == '__custom__') {
                    setState(() {
                      _isCustomSection = true;
                    });
                  } else if (val != null) {
                    setState(() {
                      _selectedSection = val;
                      _isCustomSection = false;
                    });
                    _loadAllSuggestions();
                  }
                },
              ),
              if (_isCustomSection) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customSectionController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Custom Section Name',
                    hintText: 'e.g. SMS 4 Secondary Refining, Pump Station',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 20),

              // Work Type Selector with + Add Custom Type chip
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Type of Work', style: theme.textTheme.titleSmall),
                  TextButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('+ Custom Type', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _promptAddCustomWorkType,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._availableWorkTypes.map((type) {
                    final isSelected = _selectedWorkType == type;
                    return ChoiceChip(
                      label: Text(type, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      selected: isSelected,
                      selectedColor: AppColors.primaryContainer,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedWorkType = type);
                      },
                    );
                  }),
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Type', style: TextStyle(fontSize: 12)),
                    onPressed: _promptAddCustomWorkType,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Equipment Type with Autocomplete
              Text('Equipment Name / ID', style: theme.textTheme.titleSmall),
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
                  textEditingController.addListener(() {
                    _equipmentController.text = textEditingController.text;
                  });
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Induction Coil #2, Blower Motor, ESP, Pump #1',
                      prefixIcon: Icon(Icons.precision_manufacturing_rounded),
                      helperText: 'Select existing or type any new equipment name',
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
