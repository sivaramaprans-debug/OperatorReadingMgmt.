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
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../notifiers/operator_readings_notifier.dart';
import '../notifiers/reading_form_notifier.dart';
import '../notifiers/previous_reading_provider.dart';
import '../notifiers/heat_validation_provider.dart';
import '../widgets/readings_calculated_table.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../dashboard/presentation/notifiers/operator_dashboard_notifier.dart';
import '../../../dashboard/presentation/notifiers/admin_dashboard_notifier.dart';

/// Provider to load previous readings for all assigned devices in a specific category.
final previousReadingsMapProvider = FutureProvider.autoDispose.family<Map<String, SupabaseReading>, String>((ref, category) async {
  final operator = ref.watch(authNotifierProvider.notifier).currentUser;
  if (operator == null) return {};

  final devicesRepo = ref.read(supabaseDevicesRepoProvider);
  final readingsRepo = ref.read(supabaseReadingsRepoProvider);

  final allAssigned = await devicesRepo.getAssignedToOperator(operator.id);
  final catDevices = allAssigned.where((d) => d.deviceCategory == category).toList();

  final Map<String, SupabaseReading> results = {};
  for (final d in catDevices) {
    final prev = await readingsRepo.getPreviousReading(
      deviceId: d.id,
      readingType: 'day',
      readingDateMs: AppDateUtils.nowUtcMs(),
      heatNumber: '',
    );
    if (prev != null) {
      results[d.id] = prev;
    }
  }
  return results;
});

class OperatorReadingAddScreen extends ConsumerStatefulWidget {
  const OperatorReadingAddScreen({super.key});

  @override
  ConsumerState<OperatorReadingAddScreen> createState() => _OperatorReadingAddScreenState();
}

class _OperatorReadingAddScreenState extends ConsumerState<OperatorReadingAddScreen> {
  String? _selectedDeviceId;
  String _readingType = 'day'; // 'heat' | 'day'
  final _heatNumberController = TextEditingController();
  // Map of unit -> TextEditingController for dynamic unit fields in Energy tab
  final Map<String, TextEditingController> _unitControllers = {};
  // Track current device to know when to reset controllers in Energy tab
  SupabaseDevice? _currentDevice;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  // Map of deviceId -> TextEditingController for batch entry tabs (Pollution, Water)
  final Map<String, TextEditingController> _batchControllers = {};
  bool _isSubmittingBatch = false;

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
    for (final c in _batchControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getBatchController(String deviceId) {
    return _batchControllers.putIfAbsent(deviceId, () => TextEditingController());
  }

  void _setupControllersForDevice(SupabaseDevice device) {
    if (_currentDevice?.id == device.id) return;
    // Dispose old controllers
    for (final c in _unitControllers.values) {
      c.dispose();
    }
    _unitControllers.clear();
    // Create new controllers for each unit in both device matrices
    final heatUnits = device.matrix.isEmpty
        ? <String>[]
        : device.matrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final dayUnits = device.dayMatrix.isEmpty
        ? <String>[]
        : device.dayMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final allUnits = {...heatUnits, ...dayUnits};
    for (final unit in allUnits) {
      final controller = TextEditingController();
      controller.addListener(_onUnitValuesChanged);
      _unitControllers[unit] = controller;
    }
    // Reset reading type
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

    // Power Factor validation checks
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

  Future<void> _onSubmitBatch(List<SupabaseDevice> devices, String category) async {
    final user = ref.read(authNotifierProvider.notifier).currentUser;
    if (user == null) return;

    final List<({SupabaseDevice device, double value, String unitKey})> entries = [];
    for (final d in devices) {
      final controller = _batchControllers[d.id];
      if (controller == null) continue;
      final text = controller.text.trim();
      if (text.isEmpty) continue;

      final parsed = double.tryParse(text);
      if (parsed == null) {
        SnackbarHelper.showError(context, 'Please enter a valid number for ${d.name}.');
        return;
      }
      if (parsed < 0) {
        SnackbarHelper.showError(context, 'Readings cannot be negative (${d.name}).');
        return;
      }
      final unitKey = d.singleMetric.isNotEmpty ? d.singleMetric : (d.dayMatrix.split(',').firstOrNull?.trim() ?? 'KWH');
      entries.add((device: d, value: parsed, unitKey: unitKey));
    }

    if (entries.isEmpty) {
      SnackbarHelper.showError(context, 'Please enter at least one reading.');
      return;
    }

    setState(() {
      _isSubmittingBatch = true;
    });

    final useCase = ref.read(addReadingUseCaseProvider);
    final nowMs = AppDateUtils.nowUtcMs();
    int successCount = 0;
    List<String> errors = [];

    for (final entry in entries) {
      final (_, failure) = await useCase.call(
        operatorId: user.id,
        deviceId: entry.device.id,
        readingType: 'day',
        heatNumber: '',
        values: {entry.unitKey: entry.value},
        readingDate: nowMs,
      );
      if (failure != null) {
        errors.add('${entry.device.name}: ${failure.message}');
      } else {
        successCount++;
      }
    }

    setState(() {
      _isSubmittingBatch = false;
    });

    if (!mounted) return;

    if (errors.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Batch Submission Results'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Successfully added $successCount readings.', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('Errors:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ...errors.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $e', style: const TextStyle(fontSize: 12, color: Colors.red)),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (successCount > 0) {
                  ref.invalidate(operatorDashboardStatsProvider);
                  ref.invalidate(adminDashboardStatsProvider);
                  ref.invalidate(previousReadingsMapProvider(category));
                  context.pop();
                }
              },
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } else {
      SnackbarHelper.showSuccess(context, 'Successfully added all $successCount readings.');
      ref.invalidate(operatorDashboardStatsProvider);
      ref.invalidate(adminDashboardStatsProvider);
      ref.invalidate(previousReadingsMapProvider(category));
      context.pop();
    }
  }

  Widget _buildEnergyTab(List<SupabaseDevice> allDevices, ThemeData theme, ReadingFormState formState) {
    final devices = allDevices.where((d) => d.isEnergy || d.requiresHeatDay).toList();
    if (devices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No Energy devices assigned to you.', textAlign: TextAlign.center),
        ),
      );
    }

    _selectedDeviceId ??= devices.first.id;
    final selectedDevice = devices.firstWhere(
      (d) => d.id == _selectedDeviceId,
      orElse: () => devices.first,
    );

    // Setup controllers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (_currentDevice?.id != selectedDevice.id) {
          setState(() {
            _setupControllersForDevice(selectedDevice);
          });
        }
        _onUnitValuesChanged();
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

    final currentUnits = _readingType == 'heat' && selectedDevice.requiresHeatDay ? heatUnits : dayUnits;
    final heatFactors = parseFactorMap(selectedDevice.heatUnitFactors);
    final dayFactors = parseFactorMap(selectedDevice.dayUnitFactors);
    final currentFactors = _readingType == 'heat' && selectedDevice.requiresHeatDay ? heatFactors : dayFactors;

    final selectedDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final readingDateMs = selectedDateTime.toUtc().millisecondsSinceEpoch;

    final prevReadingAsync = ref.watch(previousReadingProvider((
      deviceId: selectedDevice.id,
      readingType: _readingType,
      readingDateMs: readingDateMs,
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
            DropdownButtonFormField<String>(
              value: _selectedDeviceId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Device',
                prefixIcon: Icon(Icons.settings_input_component_outlined),
              ),
              items: devices.map((d) => DropdownMenuItem(
                value: d.id,
                child: Text(d.name, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (val) {
                if (val == null) return;
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
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              const SizedBox(height: 20),
            ],

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

            ...currentUnits.map((unit) {
              final controller = _unitControllers[unit] ?? TextEditingController();
              final prevVal = prevValues[unit];
              final mf = currentFactors[unit] ?? 1.0;
              final isCumulative = _isCumulativeUnit(unit);
              final isPfField = unit.toUpperCase() == 'PF';
              final hasKwhAndKvah = _unitControllers.keys.any((k) => k.toUpperCase() == 'KWH') &&
                  _unitControllers.keys.any((k) => k.toUpperCase() == 'KVAH');

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      readOnly: isPfField && hasKwhAndKvah,
                      decoration: InputDecoration(
                        labelText: unit,
                        prefixIcon: const Icon(Icons.electric_meter_outlined),
                        suffixText: unit,
                        filled: isPfField && hasKwhAndKvah,
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
                            if (currentVal == null || !isCumulative) {
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
  }

  Widget _buildBatchEntryTab(List<SupabaseDevice> allDevices, String category, ThemeData theme) {
    final devices = allDevices.where((d) => d.deviceCategory == category).toList();
    if (devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No ${DeviceCategory.label(category)} devices assigned to you.', textAlign: TextAlign.center),
        ),
      );
    }

    final prevReadingsAsync = ref.watch(previousReadingsMapProvider(category));

    return prevReadingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading previous readings: $e')),
      data: (prevMap) {
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final d = devices[index];
                  final controller = _getBatchController(d.id);
                  final unitKey = d.singleMetric.isNotEmpty ? d.singleMetric : (d.dayMatrix.split(',').firstOrNull?.trim() ?? 'KWH');
                  final factors = parseFactorMap(d.dayUnitFactors);
                  final mf = factors[unitKey] ?? d.multiplicationFactor;

                  double? prevVal;
                  final prevReading = prevMap[d.id];
                  if (prevReading != null) {
                    try {
                      final decoded = jsonDecode(prevReading.readingValues) as Map<String, dynamic>;
                      prevVal = (decoded[unitKey] ?? decoded.values.firstOrNull) as double?;
                    } catch (_) {}
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                    ),
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                category == DeviceCategory.water ? Icons.water_drop_rounded : Icons.air_rounded,
                                color: category == DeviceCategory.water ? Colors.blue : AppColors.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  d.name,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (mf != 1.0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'MF: ${NumberFormat('#,##0.##').format(mf)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              labelText: 'Current Reading ($unitKey)',
                              prefixIcon: const Icon(Icons.speed_rounded),
                              suffixText: unitKey,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                'Previous: ${prevVal != null ? NumberFormat('#,##0.##').format(prevVal) : '—'}',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const Spacer(),
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: controller,
                                builder: (context, value, child) {
                                  final currentVal = double.tryParse(value.text.trim());
                                  if (currentVal == null || prevVal == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final diff = currentVal - prevVal;
                                  final consump = diff * mf;
                                  final displayUnit = category == DeviceCategory.water ? 'Litres' : 'KWH';

                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Diff: ${diff.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: diff < 0 ? theme.colorScheme.error : theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '| Cons: ${NumberFormat('#,##0.##').format(consump)} $displayUnit',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: AppButton(
                  label: 'Submit All Readings',
                  isLoading: _isSubmittingBatch,
                  onPressed: () => _onSubmitBatch(devices, category),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(readingFormNotifierProvider);
    final devicesAsync = ref.watch(assignedActiveDevicesProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Reading'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.bolt_rounded), text: 'Energy'),
              Tab(icon: Icon(Icons.air_rounded), text: 'Pollution'),
              Tab(icon: Icon(Icons.water_drop_rounded), text: 'Water'),
            ],
          ),
        ),
        body: devicesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading devices: $e')),
          data: (devices) {
            return TabBarView(
              children: [
                _buildEnergyTab(devices, Theme.of(context), formState),
                _buildBatchEntryTab(devices, DeviceCategory.dedusting, Theme.of(context)),
                _buildBatchEntryTab(devices, DeviceCategory.water, Theme.of(context)),
              ],
            );
          },
        ),
      ),
    );
  }

  void _onUnitValuesChanged() {
    final kwhKey = _unitControllers.keys.firstWhere((k) => k.toUpperCase() == 'KWH', orElse: () => '');
    final kvahKey = _unitControllers.keys.firstWhere((k) => k.toUpperCase() == 'KVAH', orElse: () => '');
    final pfKey = _unitControllers.keys.firstWhere((k) => k.toUpperCase() == 'PF', orElse: () => '');

    if (kwhKey.isNotEmpty && kvahKey.isNotEmpty && pfKey.isNotEmpty) {
      final kwhCtrl = _unitControllers[kwhKey]!;
      final kvahCtrl = _unitControllers[kvahKey]!;
      final pfCtrl = _unitControllers[pfKey]!;

      final currentKwh = double.tryParse(kwhCtrl.text.trim());
      final currentKvah = double.tryParse(kvahCtrl.text.trim());

      final selectedDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final readingDateMs = selectedDateTime.toUtc().millisecondsSinceEpoch;

      final prevReading = ref.read(previousReadingProvider((
        deviceId: _selectedDeviceId ?? '',
        readingType: _readingType,
        readingDateMs: readingDateMs,
        heatNumber: _heatNumberController.text,
      ))).value;

      if (prevReading != null && currentKwh != null && currentKvah != null) {
        try {
          final prevMap = jsonDecode(prevReading.readingValues) as Map<String, dynamic>;
          final prevKwh = (prevMap[kwhKey] ?? prevMap['KWH'] ?? prevMap['kwh']) as num?;
          final prevKvah = (prevMap[kvahKey] ?? prevMap['KVAH'] ?? prevMap['kvah']) as num?;

          if (prevKwh != null && prevKvah != null) {
            final device = _currentDevice;
            if (device != null) {
              final heatFactors = parseFactorMap(device.heatUnitFactors);
              final dayFactors = parseFactorMap(device.dayUnitFactors);
              final currentFactors = _readingType == 'heat' && device.requiresHeatDay ? heatFactors : dayFactors;

              final kwhFactor = currentFactors[kwhKey] ?? 1.0;
              final kvahFactor = currentFactors[kvahKey] ?? 1.0;
              final kwhDiff = currentKwh - prevKwh.toDouble();
              final kvahDiff = currentKvah - prevKvah.toDouble();
              final kwhCons = kwhDiff * kwhFactor;
              final kvahCons = kvahDiff * kvahFactor;

              if (kvahCons > 0) {
                final calculatedPf = kwhCons / kvahCons;
                final formatted = calculatedPf.toStringAsFixed(3);
                if (pfCtrl.text != formatted) {
                  pfCtrl.value = TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(offset: formatted.length),
                  );
                }
              }
            }
          }
        } catch (_) {}
      }
    }
  }

  static bool _isCumulativeUnit(String unit) {
    final u = unit.trim().toUpperCase();
    return u == 'KWH' || u == 'KWHLT' || u == 'KVAH' || u == 'KVARH';
  }
}

/// Standalone widget for real-time heat number validation hint.
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
          if (heatText.isEmpty) {
            return Text(
              'Enter the next heat number. A new cycle must start from Heat #1.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            );
          }

          if (result.isValid) {
            return Row(
              children: [
                Icon(Icons.check_circle_outline, size: 14, color: theme.colorScheme.primary),
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

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 14, color: theme.colorScheme.error),
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

        final bgColor = isInvalid ? Colors.red.shade50 : const Color(0xFFE8F5E9);
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
