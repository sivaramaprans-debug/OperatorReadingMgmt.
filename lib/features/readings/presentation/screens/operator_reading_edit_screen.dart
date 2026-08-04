import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/form_container.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../notifiers/reading_form_notifier.dart';
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
  bool _loadingDevice = true;

  @override
  void initState() {
    super.initState();
    final r = widget.reading;
    _readingType = r?.readingType ?? 'day';
    _heatNumberController = TextEditingController(text: r?.heatNumber ?? '');
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    final r = widget.reading;
    if (r == null) {
      setState(() => _loadingDevice = false);
      return;
    }
    try {
      final device = await ref.read(supabaseDevicesRepoProvider).findById(r.deviceId);
      if (mounted) {
        setState(() {
          _device = device;
          _loadingDevice = false;
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
              _unitControllers[unit] = TextEditingController(
                text: existingValues.containsKey(unit) ? existingValues[unit]!.toStringAsFixed(2) : '',
              );
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDevice = false);
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
      context.pop();
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

    final todayMidnight = AppDateUtils.todayLocalMidnightUtcMs();
    final canEdit = r.readingDate == todayMidnight;

    if (!canEdit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Reading')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This reading cannot be edited because it is from a previous day.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    if (_loadingDevice) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Reading')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final formState = ref.watch(readingFormNotifierProvider);
    final requiresHeatDay = _device?.requiresHeatDay ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Reading')),
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
              ...(_readingType == 'heat' && requiresHeatDay ? _heatUnits : _dayUnits).map((unit) {
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
