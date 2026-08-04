import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/form_container.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../notifiers/operator_readings_notifier.dart';
import '../notifiers/reading_form_notifier.dart';
import '../notifiers/previous_reading_provider.dart';
import '../notifiers/heat_validation_provider.dart';
import '../widgets/readings_calculated_table.dart';

class OperatorReadingAddScreen extends ConsumerStatefulWidget {
  const OperatorReadingAddScreen({super.key});

  @override
  ConsumerState<OperatorReadingAddScreen> createState() => _OperatorReadingAddScreenState();
}

class _OperatorReadingAddScreenState extends ConsumerState<OperatorReadingAddScreen> {
  String? _selectedDeviceId;
  String _readingType = 'day'; // 'heat' | 'day'
  final _heatNumberController = TextEditingController();
  // Map of unit -> TextEditingController for dynamic unit fields
  final Map<String, TextEditingController> _unitControllers = {};
  // Track current device to know when to reset controllers
  SupabaseDevice? _currentDevice;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedTime = TimeOfDay.now();
    _heatNumberController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _heatNumberController.dispose();
    for (final c in _unitControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _setupControllersForDevice(SupabaseDevice device) {
    if (_currentDevice?.id == device.id) return;
    // Dispose old controllers
    for (final c in _unitControllers.values) {
      c.dispose();
    }
    _unitControllers.clear();
    // Create new controllers for each unit in the device matrix
    // Create new controllers for each unit in both device matrices
    final heatUnits = device.matrix.isEmpty
        ? <String>[]
        : device.matrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final dayUnits = device.dayMatrix.isEmpty
        ? <String>[]
        : device.dayMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final allUnits = {...heatUnits, ...dayUnits};
    for (final unit in allUnits) {
      _unitControllers[unit] = TextEditingController();
    }
    // Reset reading type — default to 'day'; if device requires heat/day the operator picks.
    _readingType = device.requiresHeatDay ? 'heat' : 'day';
    _heatNumberController.clear();
    _currentDevice = device;
  }

  Future<void> _onSubmit(SupabaseDevice device) async {
    // Validate heat number first if this is a heat reading
    if (_readingType == 'heat' && device.requiresHeatDay) {
      final heatText = _heatNumberController.text.trim();
      if (heatText.isEmpty) {
        SnackbarHelper.showError(context, 'Please enter a Heat Number.');
        return;
      }
      final useCase = ref.read(validateHeatNumberUseCaseProvider);
      final result = await useCase.call(
        deviceId: device.id,
        heatNumberText: heatText,
      );
      if (!result.isValid) {
        if (!mounted) return;
        SnackbarHelper.showError(context, result.error!);
        return;
      }
    }

    // Collect all unit values
    final Map<String, double> values = {};
    // Determine which matrix to read from based on the reading type.
    // If the device doesn't have heat/day toggle, always use day units.
    final currentUnits = _readingType == 'heat' && device.requiresHeatDay
        ? (device.matrix.isEmpty ? [] : device.matrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList())
        : (device.dayMatrix.isEmpty ? [] : device.dayMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());

    for (final unit in currentUnits) {
      final controller = _unitControllers[unit];
      if (controller == null) continue;
      final parsed = double.tryParse(controller.text.trim());
      if (parsed == null) {
        SnackbarHelper.showError(context, 'Please enter a valid number for $unit.');
        return;
      }
      values[unit] = parsed;
    }

    if (values.isEmpty) {
      SnackbarHelper.showError(context, 'No units configured for this device. Contact admin.');
      return;
    }

    // ── Power Factor (PF) Validation ──────────────────────────────────────
    // 1. Direct PF matrix unit check
    final directPfKey = values.keys.firstWhere((k) => k.toUpperCase() == 'PF', orElse: () => '');
    if (directPfKey.isNotEmpty && (values[directPfKey] ?? 0) > 1.0) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Invalid Power Factor (PF)'),
            ],
          ),
          content: Text(
            'Entered Power Factor (${values[directPfKey]}) is greater than 1.0!\n\nPower Factor must be less than or equal to 1.0. Please check your reading.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Check Readings'),
            ),
          ],
        ),
      );
      return;
    }

    // 2. Dynamic PF calculation from consumption (KWH Consumption / KVAH Consumption)
    final kwhKey = values.keys.firstWhere((k) => k.toUpperCase() == 'KWH', orElse: () => '');
    final kvahKey = values.keys.firstWhere((k) => k.toUpperCase() == 'KVAH', orElse: () => '');

    if (kwhKey.isNotEmpty && kvahKey.isNotEmpty) {
      final repo = ref.read(supabaseReadingsRepoProvider);
      final prevReading = await repo.getPreviousReading(
        deviceId: device.id,
        readingType: _readingType,
        readingDateMs: AppDateUtils.nowUtcMs(),
        heatNumber: _heatNumberController.text,
      );

      if (prevReading != null) {
        try {
          final prevMap = jsonDecode(prevReading.readingValues) as Map<String, dynamic>;
          final prevKwh = (prevMap[kwhKey] ?? prevMap['KWH'] ?? prevMap['kwh']) as num?;
          final prevKvah = (prevMap[kvahKey] ?? prevMap['KVAH'] ?? prevMap['kvah']) as num?;

          if (prevKwh != null && prevKvah != null) {
            Map<String, double> factorMap = {};
            try {
              final rawJson = _readingType == 'heat' ? device.heatUnitFactors : device.dayUnitFactors;
              if (rawJson.isNotEmpty && rawJson != '{}') {
                factorMap = (jsonDecode(rawJson) as Map<String, dynamic>)
                    .map((k, v) => MapEntry(k, (v as num).toDouble()));
              }
            } catch (_) {}

            final kwhFactor = factorMap[kwhKey] ?? factorMap['KWH'] ?? 1.0;
            final kvahFactor = factorMap[kvahKey] ?? factorMap['KVAH'] ?? 1.0;

            final kwhDiff = values[kwhKey]! - prevKwh.toDouble();
            final kvahDiff = values[kvahKey]! - prevKvah.toDouble();
            final kwhCons = kwhDiff * kwhFactor;
            final kvahCons = kvahDiff * kvahFactor;

            if (kvahCons > 0) {
              final calculatedPf = kwhCons / kvahCons;
              if (calculatedPf > 1.0) {
                if (!mounted) return;
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Power Factor Error'),
                      ],
                    ),
                    content: Text(
                      'Auto-calculated Power Factor (PF = ${calculatedPf.toStringAsFixed(3)}) from consumption '
                      '(${kwhCons.toStringAsFixed(2)} KWH / ${kvahCons.toStringAsFixed(2)} KVAH) is greater than 1.0!\n\n'
                      'Power Factor must be less than or equal to 1.0. Please check your readings.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Check Readings'),
                      ),
                    ],
                  ),
                );
                return;
              }
              values['PF'] = double.parse(calculatedPf.toStringAsFixed(3));
            }
          }
        } catch (_) {}
      }
    }

    final selectedDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final readingDateMs = selectedDateTime.toUtc().millisecondsSinceEpoch;

    final notifier = ref.read(readingFormNotifierProvider.notifier);
    await notifier.submitReading(
      deviceId: device.id,
      readingType: _readingType,
      heatNumber: _heatNumberController.text,
      values: values,
      readingDate: readingDateMs,
    );

    if (!mounted) return;

    final state = ref.read(readingFormNotifierProvider);
    if (state.success) {
      SnackbarHelper.showSuccess(context, 'Reading added successfully');
      context.pop();
    } else if (state.error != null) {
      SnackbarHelper.showError(context, state.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(readingFormNotifierProvider);
    final devicesAsync = ref.watch(assignedActiveDevicesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Reading')),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading devices: $e')),
        data: (devices) {
          if (devices.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No devices assigned to you.\nContact your administrator.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Auto-select first device if none selected
          _selectedDeviceId ??= devices.first.id;
          final selectedDevice = devices.firstWhere(
            (d) => d.id == _selectedDeviceId,
            orElse: () => devices.first,
          );

          // Setup controllers for the selected device
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _currentDevice?.id != selectedDevice.id) {
              setState(() {
                _setupControllersForDevice(selectedDevice);
              });
            }
          });
          if (_currentDevice == null) {
            _setupControllersForDevice(selectedDevice);
          }

          final heatUnits = selectedDevice.matrix.isEmpty
              ? <String>[]
              : selectedDevice.matrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          final dayUnits = selectedDevice.dayMatrix.isEmpty
              ? <String>[]
              : selectedDevice.dayMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

          // Use heat units only when device requires heat/day AND current type is heat.
          // Otherwise always use day units (including when heat/day toggle is disabled).
          final currentUnits = _readingType == 'heat' && selectedDevice.requiresHeatDay ? heatUnits : dayUnits;
          
          final heatFactors = parseFactorMap(selectedDevice.heatUnitFactors);
          final dayFactors = parseFactorMap(selectedDevice.dayUnitFactors);
          final currentFactors = _readingType == 'heat' && selectedDevice.requiresHeatDay ? heatFactors : dayFactors;
          
          final todayMidnight = AppDateUtils.todayLocalMidnightUtcMs();
          final prevReadingAsync = ref.watch(previousReadingProvider((
            deviceId: selectedDevice.id,
            readingType: _readingType,
            readingDateMs: todayMidnight,
            heatNumber: _heatNumberController.text,
          )));
          
          Map<String, double> prevValues = {};
          if (prevReadingAsync.value != null) {
            try {
              final decoded = jsonDecode(prevReadingAsync.value!.readingValues) as Map<String, dynamic>;
              prevValues = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
            } catch (_) {}
          }

          return FormContainer(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Device selector
                  DropdownButtonFormField<String>(
                    value: _selectedDeviceId,
                    decoration: const InputDecoration(
                      labelText: 'Device',
                      prefixIcon: Icon(Icons.settings_input_component_outlined),
                    ),
                    items: devices.map((d) {
                      return DropdownMenuItem(
                        value: d.id,
                        child: Text(d.name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedDeviceId = val;
                        final newDevice = devices.firstWhere((d) => d.id == val);
                        _setupControllersForDevice(newDevice);
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Date & Time selection
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_today_rounded),
                          title: const Text('Date'),
                          subtitle: Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2101),
                            );
                            if (picked != null) {
                              setState(() => _selectedDate = picked);
                            }
                          },
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

                  // Matrix info chip
                  if (currentUnits.isNotEmpty) ...[
                    Text('${_readingType == 'heat' && selectedDevice.requiresHeatDay ? 'Heat' : 'Day'} Units', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: currentUnits.map((u) => Chip(
                        label: Text(u, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )).toList(),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'No matrix units assigned to this device. Contact admin.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Heat / Day selection (only for devices that require it)
                  if (selectedDevice.requiresHeatDay) ...[
                    Text('Reading Type', style: theme.textTheme.titleSmall),
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
                    const SizedBox(height: 8),
                    if (_readingType == 'heat') ...[
                      TextField(
                        controller: _heatNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Heat Number',
                          prefixIcon: Icon(Icons.tag_rounded),
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                      ),
                      _HeatHintWidget(
                        deviceId: selectedDevice.id,
                        heatNumberController: _heatNumberController,
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],

                  // Dynamic unit value fields
                  ...currentUnits.map((unit) {
                    final controller = _unitControllers[unit] ?? TextEditingController();
                    final prevVal = prevValues[unit];
                    final mf = currentFactors[unit] ?? 1.0;
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              labelText: unit,
                              prefixIcon: const Icon(Icons.electric_meter_outlined),
                              suffixText: unit,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textInputAction: TextInputAction.next,
                          ),
                          if (prevVal != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 12),
                              child: ValueListenableBuilder<TextEditingValue>(
                                valueListenable: controller,
                                builder: (context, value, child) {
                                  final currentVal = double.tryParse(value.text.trim());
                                  if (currentVal == null) {
                                    return Text('Prev: ${prevVal.toStringAsFixed(2)}', 
                                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
                                  }
                                  final diff = currentVal - prevVal;
                                  final consump = diff * mf;
                                  
                                  final Color diffColor = diff < 0 ? theme.colorScheme.error : theme.colorScheme.primary;
                                  return Row(
                                    children: [
                                      Text('Prev: ${prevVal.toStringAsFixed(2)}  |  ', 
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                      Text('Diff: ${diff.toStringAsFixed(2)}', 
                                        style: theme.textTheme.bodySmall?.copyWith(color: diffColor, fontWeight: FontWeight.bold)),
                                      Text('  |  Consump: ${consump.toStringAsFixed(2)}', 
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                                    ],
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  }),

                  // Live Power Factor (PF) Appearance & Validation Banner
                  _LivePowerFactorWidget(
                    unitControllers: _unitControllers,
                    prevValues: prevValues,
                    currentFactors: currentFactors,
                  ),

                  const SizedBox(height: 8),

                  AppButton(
                    label: 'Submit Reading',
                    isLoading: formState.isLoading,
                    onPressed: currentUnits.isEmpty ? null : () => _onSubmit(selectedDevice),
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

/// Standalone widget for real-time heat number validation hint.
/// Extracted to avoid DDC compiler crash with complex nested closures.
class _HeatHintWidget extends ConsumerStatefulWidget {
  const _HeatHintWidget({
    required this.deviceId,
    required this.heatNumberController,
  });

  final String deviceId;
  final TextEditingController heatNumberController;

  @override
  ConsumerState<_HeatHintWidget> createState() => _HeatHintWidgetState();
}

class _HeatHintWidgetState extends ConsumerState<_HeatHintWidget> {
  String _lastHeatText = '';

  @override
  void initState() {
    super.initState();
    widget.heatNumberController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = widget.heatNumberController.text.trim();
    if (text != _lastHeatText) {
      setState(() => _lastHeatText = text);
    }
  }

  @override
  void dispose() {
    widget.heatNumberController.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heatText = _lastHeatText;

    final validationAsync = ref.watch(heatValidationProvider((
      deviceId: widget.deviceId,
      heatNumber: heatText,
    )));

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12),
      child: validationAsync.when(
        loading: () => const SizedBox(
          height: 2,
          child: LinearProgressIndicator(),
        ),
        error: (_, __) => const SizedBox.shrink(),
        data: (result) {
          // Empty field — show static "expected next" hint
          if (heatText.isEmpty) {
            return Text(
              'Enter the next heat number. A new cycle must start from Heat #1.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }

          // Valid
          if (result.isValid) {
            return Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Heat #$heatText is valid ✓',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }

          // Invalid
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline,
                  size: 14, color: theme.colorScheme.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  result.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Standalone widget for live Power Factor (PF) appearance box & validation alert.
class _LivePowerFactorWidget extends StatelessWidget {
  const _LivePowerFactorWidget({
    required this.unitControllers,
    required this.prevValues,
    required this.currentFactors,
  });

  final Map<String, TextEditingController> unitControllers;
  final Map<String, double> prevValues;
  final Map<String, double> currentFactors;

  @override
  Widget build(BuildContext context) {
    final kwhKey = unitControllers.keys.firstWhere(
      (k) => k.toUpperCase() == 'KWH',
      orElse: () => '',
    );
    final kvahKey = unitControllers.keys.firstWhere(
      (k) => k.toUpperCase() == 'KVAH',
      orElse: () => '',
    );
    final pfKey = unitControllers.keys.firstWhere(
      (k) => k.toUpperCase() == 'PF',
      orElse: () => '',
    );

    final kwhCtrl = kwhKey.isNotEmpty ? unitControllers[kwhKey] : null;
    final kvahCtrl = kvahKey.isNotEmpty ? unitControllers[kvahKey] : null;
    final pfCtrl = pfKey.isNotEmpty ? unitControllers[pfKey] : null;

    final Listenable listenable = Listenable.merge([
      if (kwhCtrl != null) kwhCtrl,
      if (kvahCtrl != null) kvahCtrl,
      if (pfCtrl != null) pfCtrl,
    ]);

    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        double? calculatedPf;
        double? kwhCons;
        double? kvahCons;

        if (kwhCtrl != null && kvahCtrl != null) {
          final currentKwh = double.tryParse(kwhCtrl.text.trim());
          final currentKvah = double.tryParse(kvahCtrl.text.trim());
          final prevKwh = prevValues[kwhKey];
          final prevKvah = prevValues[kvahKey];

          if (currentKwh != null && currentKvah != null && prevKwh != null && prevKvah != null) {
            final kwhFactor = currentFactors[kwhKey] ?? 1.0;
            final kvahFactor = currentFactors[kvahKey] ?? 1.0;
            final kwhDiff = currentKwh - prevKwh;
            final kvahDiff = currentKvah - prevKvah;
            kwhCons = kwhDiff * kwhFactor;
            kvahCons = kvahDiff * kvahFactor;

            if (kvahCons > 0) {
              calculatedPf = kwhCons / kvahCons;
            }
          }
        }

        double? directPf;
        if (pfCtrl != null) {
          directPf = double.tryParse(pfCtrl.text.trim());
        }

        final activePf = calculatedPf ?? directPf;
        if (activePf == null) return const SizedBox.shrink();

        final isInvalid = activePf > 1.0;

        final bgColor = isInvalid
            ? Colors.red.shade50
            : const Color(0xFFE8F5E9);
        final borderColor = isInvalid ? Colors.red.shade400 : Colors.teal.shade400;
        final textColor = isInvalid ? Colors.red.shade900 : Colors.teal.shade900;
        final icon = isInvalid ? Icons.warning_amber_rounded : Icons.check_circle_rounded;

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: isInvalid ? Colors.red.withOpacity(0.1) : Colors.teal.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: textColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Power Factor (PF): ${activePf.toStringAsFixed(3)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isInvalid ? Colors.red.shade200 : Colors.teal.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isInvalid ? 'INVALID (PF > 1.0)' : 'VALID',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isInvalid
                    ? '⚠️ Warning: Auto-calculated Power Factor from consumption (${kwhCons?.toStringAsFixed(2)} KWH / ${kvahCons?.toStringAsFixed(2)} KVAH) is greater than 1.0! Power Factor must be ≤ 1.0. Please verify your readings.'
                    : '✓ Calculated from consumption (${kwhCons?.toStringAsFixed(2)} KWH / ${kvahCons?.toStringAsFixed(2)} KVAH). Readings are within normal limits.',
                style: TextStyle(
                  fontSize: 12,
                  color: textColor.withOpacity(0.9),
                  height: 1.3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
