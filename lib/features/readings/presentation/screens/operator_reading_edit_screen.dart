import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/form_container.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../notifiers/reading_form_notifier.dart';
import '../notifiers/previous_reading_provider.dart';
import '../widgets/live_power_factor_widget.dart';

class OperatorReadingEditScreen extends ConsumerStatefulWidget {
  const OperatorReadingEditScreen({super.key, required this.readingId, this.reading});
  final String readingId;
  final SupabaseReading? reading;

  @override
  ConsumerState<OperatorReadingEditScreen> createState() => _OperatorReadingEditScreenState();
}

class _OperatorReadingEditScreenState extends ConsumerState<OperatorReadingEditScreen> {
  late String _readingType;
  late final TextEditingController _heatNumberController;
  final Map<String, TextEditingController> _unitControllers = {};
  SupabaseDevice? _device;
  List<String> _heatUnits = [];
  List<String> _dayUnits = [];
  bool _loading = true;
  bool _canEdit = true;
  String? _cannotEditReason;

  @override
  void initState() {
    super.initState();
    final r = widget.reading;
    _readingType = r?.readingType ?? 'day';
    _heatNumberController = TextEditingController(text: r?.heatNumber ?? '');
    _heatNumberController.addListener(() => setState(() {}));
    _loadData();
  }

  Future<void> _loadData() async {
    final r = widget.reading;
    if (r == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final readingsRepo = ref.read(supabaseReadingsRepoProvider);
      final isLatest = await readingsRepo.isLatestReadingForDevice(
        deviceId: r.deviceId,
        readingId: r.id,
      );

      if (!isLatest) {
        if (mounted) {
          setState(() {
            _canEdit = false;
            _cannotEditReason = 'This reading cannot be edited because newer readings have already been recorded for this device. Only the last entered reading can be edited.';
            _loading = false;
          });
        }
        return;
      }

      final device = await ref.read(supabaseDevicesRepoProvider).findById(r.deviceId);
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
            
            // Parse existing values and pre-populate controllers
            Map<String, double> existingValues = {};
            try {
              final decoded = jsonDecode(r.readingValues) as Map<String, dynamic>;
              existingValues = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
            } catch (_) {}

            final allUnits = {..._heatUnits, ..._dayUnits};
            for (final unit in allUnits) {
              final controller = TextEditingController(
                text: existingValues.containsKey(unit) ? existingValues[unit]!.toStringAsFixed(2) : '',
              );
              controller.addListener(_onUnitValuesChanged);
              _unitControllers[unit] = controller;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
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

      final r = widget.reading;
      if (r == null) return;

      final prevReading = ref.read(previousReadingProvider((
        deviceId: r.deviceId,
        readingType: _readingType,
        readingDateMs: r.readingDate,
        heatNumber: _heatNumberController.text,
        excludeReadingId: widget.readingId,
      ))).value;

      if (prevReading != null && currentKwh != null && currentKvah != null) {
        try {
          final prevMap = jsonDecode(prevReading.readingValues) as Map<String, dynamic>;
          final prevKwh = (prevMap[kwhKey] ?? prevMap['KWH'] ?? prevMap['kwh']) as num?;
          final prevKvah = (prevMap[kvahKey] ?? prevMap['KVAH'] ?? prevMap['kvah']) as num?;

          if (prevKwh != null && prevKvah != null) {
            final device = _device;
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

  Map<String, double> parseFactorMap(String json) {
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _onSubmit() async {
    final currentUnits = _readingType == 'heat' && (_device?.requiresHeatDay ?? false)
        ? _heatUnits
        : _dayUnits;

    final Map<String, double> values = {};
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

    final notifier = ref.read(readingFormNotifierProvider.notifier);
    await notifier.editReading(
      readingId: widget.readingId,
      readingType: _readingType,
      heatNumber: _heatNumberController.text,
      values: values,
    );

    if (!mounted) return;

    final state = ref.read(readingFormNotifierProvider);
    if (state.success) {
      SnackbarHelper.showSuccess(context, 'Reading updated successfully');
      context.pop(true);
    } else if (state.error != null) {
      SnackbarHelper.showError(context, state.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reading;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Reading')),
        body: const Center(child: Text('Reading data missing')),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Reading')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_canEdit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Reading')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                Text(
                  _cannotEditReason ?? 'This reading cannot be edited.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final formState = ref.watch(readingFormNotifierProvider);
    final requiresHeatDay = _device?.requiresHeatDay ?? false;

    final prevReadingAsync = ref.watch(previousReadingProvider((
      deviceId: r.deviceId,
      readingType: _readingType,
      readingDateMs: r.readingDate,
      heatNumber: _heatNumberController.text,
      excludeReadingId: widget.readingId,
    )));

    Map<String, double> prevValues = {};
    if (prevReadingAsync.value != null) {
      try {
        final decoded = jsonDecode(prevReadingAsync.value!.readingValues) as Map<String, dynamic>;
        prevValues = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
      } catch (_) {}
    }

    final heatFactors = parseFactorMap(_device?.heatUnitFactors ?? '{}');
    final dayFactors = parseFactorMap(_device?.dayUnitFactors ?? '{}');
    final currentFactors = _readingType == 'heat' && requiresHeatDay ? heatFactors : dayFactors;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _onUnitValuesChanged();
      }
    });

    final currentUnits = _readingType == 'heat' && requiresHeatDay ? _heatUnits : _dayUnits;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Last Reading')),
      body: FormContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Device read-only info
              TextFormField(
                initialValue: _device?.name ?? r.deviceId,
                decoration: const InputDecoration(
                  labelText: 'Device',
                  enabled: false,
                  prefixIcon: Icon(Icons.settings_input_component_outlined),
                ),
              ),
              const SizedBox(height: 24),

              // Heat / Day type (only for devices that require it)
              if (requiresHeatDay) ...[
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
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));
                              }
                              final diff = currentVal - prevVal;
                              final consump = diff * mf;

                              final Color diffColor = diff < 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
                              return Row(
                                children: [
                                  Text('Prev: ${prevVal.toStringAsFixed(2)}  |  ',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  Text('Diff: ${diff.toStringAsFixed(2)}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: diffColor, fontWeight: FontWeight.bold)),
                                  Text('  |  Consump: ${consump.toStringAsFixed(2)}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),

              if (_device != null)
                LivePowerFactorWidget(
                  unitControllers: _unitControllers,
                  prevValues: prevValues,
                  currentFactors: currentFactors,
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

