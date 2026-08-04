import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/form_container.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../notifiers/admin_readings_notifier.dart';
import '../notifiers/admin_reading_form_notifier.dart';
import '../widgets/live_power_factor_widget.dart';

class AdminReadingEditScreen extends ConsumerStatefulWidget {
  const AdminReadingEditScreen({
    super.key, 
    this.readingId, 
    this.reading,
  });
  final String? readingId;
  final SupabaseReading? reading;

  @override
  ConsumerState<AdminReadingEditScreen> createState() => _AdminReadingEditScreenState();
}

class _AdminReadingEditScreenState extends ConsumerState<AdminReadingEditScreen> {
  late String _readingType;
  late final TextEditingController _heatNumberController;
  final Map<String, TextEditingController> _unitControllers = {};
  
  String? _selectedDeviceId;
  String? _selectedOperatorId;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  
  SupabaseDevice? _device;
  List<String> _heatUnits = [];
  List<String> _dayUnits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final r = widget.reading;
    _readingType = r?.readingType ?? 'day';
    _heatNumberController = TextEditingController(text: r?.heatNumber ?? '');
    _selectedDeviceId = r?.deviceId;
    _selectedOperatorId = r?.operatorId;
    
    if (r != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true).toLocal();
      _selectedDate = DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal();
      _selectedTime = TimeOfDay.fromDateTime(dt);
    } else {
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now();
    }
    
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      if (_selectedDeviceId != null) {
        await _fetchDeviceDetails(_selectedDeviceId!);
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchDeviceDetails(String deviceId) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final device = await ref.read(supabaseDevicesRepoProvider).findById(deviceId);
    if (mounted) {
      setState(() {
        _device = device;
        _loading = false;
        if (device != null) {
          _heatUnits = device.matrix.isEmpty
              ? []
              : device.matrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          _dayUnits = device.dayMatrix.isEmpty
              ? []
              : device.dayMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              
          // Parse existing values if this is an edit
          Map<String, double> existingValues = {};
          if (widget.reading != null && widget.reading!.deviceId == deviceId) {
            try {
              final decoded = jsonDecode(widget.reading!.readingValues) as Map<String, dynamic>;
              existingValues = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
            } catch (_) {}
          }

          _unitControllers.clear();
          final allUnits = {..._heatUnits, ..._dayUnits};
          for (final unit in allUnits) {
            _unitControllers[unit] = TextEditingController(
              text: existingValues.containsKey(unit) ? existingValues[unit]!.toStringAsFixed(2) : '',
            );
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _heatNumberController.dispose();
    for (final c in _unitControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _onSubmit() async {
    if (_selectedDeviceId == null || _selectedOperatorId == null) {
      SnackbarHelper.showError(context, 'Please select both a Device and an Operator.');
      return;
    }
    
    // Use heat units only when device requires heat/day AND current type is heat.
    // Otherwise always use day units.
    final currentUnits = _readingType == 'heat' && (_device?.requiresHeatDay ?? false)
        ? _heatUnits
        : _dayUnits;

    final Map<String, double> values = {};
    for (final unit in currentUnits) {
      final controller = _unitControllers[unit];
      if (controller == null) continue;
      if (controller.text.trim().isEmpty) continue; // Allow missing values for admin if needed, or enforce them? We'll enforce them.
      
      final parsed = double.tryParse(controller.text.trim());
      if (parsed == null) {
        SnackbarHelper.showError(context, 'Please enter a valid number for $unit.');
        return;
      }
      values[unit] = parsed;
    }
    
    if (values.isEmpty) {
      SnackbarHelper.showError(context, 'Please enter at least one reading value.');
      return;
    }

    final selectedDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final readingDateMs = selectedDateTime.toUtc().millisecondsSinceEpoch;
    final notifier = ref.read(adminReadingFormNotifierProvider.notifier);
    
    if (widget.readingId != null) {
      await notifier.editReading(
        readingId: widget.readingId!,
        readingDate: readingDateMs,
        readingType: _readingType,
        heatNumber: _heatNumberController.text,
        values: values,
      );
    } else {
      await notifier.submitReading(
        operatorId: _selectedOperatorId!,
        deviceId: _selectedDeviceId!,
        readingDate: readingDateMs,
        readingType: _readingType,
        heatNumber: _heatNumberController.text,
        values: values,
      );
    }

    if (!mounted) return;

    final state = ref.read(adminReadingFormNotifierProvider);
    if (state.success) {
      SnackbarHelper.showSuccess(context, 'Reading saved successfully');
      ref.invalidate(adminReadingsProvider);
      context.pop();
    } else if (state.error != null) {
      SnackbarHelper.showError(context, state.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(adminReadingFormNotifierProvider);
    final isEdit = widget.readingId != null;
    
    final devicesAsync = ref.watch(allDevicesProvider);
    final operatorsAsync = ref.watch(allOperatorsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Reading (Admin)' : 'Add Reading')),
      body: FormContainer(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
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
                            title: const Text('Date'),
                            subtitle: Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                            onTap: () => _selectDate(context),
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.access_time_rounded),
                            title: const Text('Time'),
                            subtitle: Text(_selectedTime.format(context)),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: _selectedTime,
                              );
                              if (picked != null) {
                                setState(() => _selectedTime = picked);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Operator Dropdown
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Operator',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      value: _selectedOperatorId,
                      items: operatorsAsync.value?.map((op) {
                        return DropdownMenuItem(
                          value: op.id,
                          child: Text(op.username),
                        );
                      }).toList() ?? [],
                      onChanged: (val) {
                        setState(() => _selectedOperatorId = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Device Dropdown
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Device',
                        prefixIcon: Icon(Icons.settings_input_component_outlined),
                      ),
                      value: _selectedDeviceId,
                      items: devicesAsync.value?.map((dev) {
                        return DropdownMenuItem(
                          value: dev.id,
                          child: Text(dev.name),
                        );
                      }).toList() ?? [],
                      onChanged: isEdit 
                        ? null // Don't allow changing device when editing
                        : (val) {
                          setState(() {
                            _selectedDeviceId = val;
                          });
                          if (val != null) {
                            _fetchDeviceDetails(val);
                          }
                      },
                    ),
                    const SizedBox(height: 24),

                    // Dynamic fields based on device
                    if (_device != null) ...[
                      if (_device!.requiresHeatDay) ...[
                        Text('Reading Type', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('Heat'),
                                value: 'heat',
                                groupValue: _readingType,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) => setState(() => _readingType = val!),
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('Day'),
                                value: 'day',
                                groupValue: _readingType,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) => setState(() => _readingType = val!),
                              ),
                            ),
                          ],
                        ),
                        if (_readingType == 'heat') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _heatNumberController,
                            decoration: const InputDecoration(
                              labelText: 'Heat Number',
                              prefixIcon: Icon(Icons.tag_rounded),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],

                      // Dynamic per-unit fields
                      ...(_readingType == 'heat' && _device!.requiresHeatDay ? _heatUnits : _dayUnits).map((unit) {
                        final controller = _unitControllers[unit] ?? TextEditingController();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              labelText: unit,
                              prefixIcon: const Icon(Icons.electric_meter_outlined),
                              suffixText: unit,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textInputAction: TextInputAction.next,
                          ),
                        );
                      }),
                    ] else if (!isEdit) ...[
                      const Center(child: Text('Please select a device.')),
                    ],

                    const SizedBox(height: 16),

                    if (_device != null)
                      LivePowerFactorWidget(
                        unitControllers: _unitControllers,
                        prevValues: const {},
                        currentFactors: const {},
                      ),

                    AppButton(
                      label: 'Save Changes',
                      isLoading: formState.isLoading,
                      onPressed: _onSubmit,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
