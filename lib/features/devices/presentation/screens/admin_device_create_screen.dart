import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/form_container.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../notifiers/device_form_notifier.dart';

class AdminDeviceCreateScreen extends ConsumerStatefulWidget {
  const AdminDeviceCreateScreen({super.key});

  @override
  ConsumerState<AdminDeviceCreateScreen> createState() => _AdminDeviceCreateScreenState();
}

class _AdminDeviceCreateScreenState extends ConsumerState<AdminDeviceCreateScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedHeatUnits = {};
  final Set<String> _selectedDayUnits = {};
  final Map<String, TextEditingController> _heatFactorControllers = {};
  final Map<String, TextEditingController> _dayFactorControllers = {};
  final List<String> _customUnits = [];
  bool _requiresHeatDay = false;

  void _showAddCustomMetricDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Custom Metric'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Metric Name (e.g. KVARH, TEMP)',
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim().toUpperCase();
              if (name.isNotEmpty) {
                setState(() {
                  if (!_customUnits.contains(name)) {
                    _customUnits.add(name);
                  }
                  _selectedDayUnits.add(name);
                  _dayFactorCtrl(name);
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  TextEditingController _heatFactorCtrl(String unit) =>
      _heatFactorControllers.putIfAbsent(unit, () => TextEditingController(text: '1.0'));

  TextEditingController _dayFactorCtrl(String unit) =>
      _dayFactorControllers.putIfAbsent(unit, () => TextEditingController(text: '1.0'));

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _heatFactorControllers.values) c.dispose();
    for (final c in _dayFactorControllers.values) c.dispose();
    super.dispose();
  }

  Map<String, double> _buildFactorMap(Set<String> units, Map<String, TextEditingController> controllers) {
    final map = <String, double>{};
    for (final unit in units) {
      map[unit] = double.tryParse(controllers[unit]?.text ?? '') ?? 1.0;
    }
    return map;
  }

  Future<void> _onSubmit() async {
    final notifier = ref.read(deviceFormNotifierProvider.notifier);
    // If requiresHeatDay is false, matrix is empty (no heat units needed) and all selected units go to dayMatrix.
    // If requiresHeatDay is true, matrix gets heat units and dayMatrix gets day units.
    final finalHeatUnits = _requiresHeatDay ? _selectedHeatUnits : <String>{};
    final finalDayUnits = _requiresHeatDay ? _selectedDayUnits : _selectedDayUnits;

    await notifier.createDevice(
      _nameController.text,
      1.0,
      matrix: finalHeatUnits.toList(),
      dayMatrix: finalDayUnits.toList(),
      requiresHeatDay: _requiresHeatDay,
      heatUnitFactors: _buildFactorMap(finalHeatUnits, _heatFactorControllers),
      dayUnitFactors: _buildFactorMap(finalDayUnits, _dayFactorControllers),
    );

    if (!mounted) return;
    final state = ref.read(deviceFormNotifierProvider);
    if (state.success) {
      SnackbarHelper.showSuccess(context, 'Device created successfully');
      context.pop();
    } else if (state.error != null) {
      SnackbarHelper.showError(context, state.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(deviceFormNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Device')),
      body: FormContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Device Name',
                  hintText: 'e.g. Meter A',
                  prefixIcon: Icon(Icons.settings_input_component_outlined),
                ),
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 20),

              // Heat / Day Toggle
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  title: const Text('Requires Heat / Day Entry'),
                  subtitle: const Text('Enable to allow both Heat and Day entry types separately'),
                  value: _requiresHeatDay,
                  onChanged: (val) => setState(() => _requiresHeatDay = val),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                ),
              ),
              const SizedBox(height: 24),

              // ── Day Matrix (Default) ──────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _requiresHeatDay ? 'Day Units' : 'Matrix Units (Day Entry Default)',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Add Custom Metric'),
                    onPressed: _showAddCustomMetricDialog,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Select all units that apply to day readings', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [...AppConstants.matrixUnits, ..._customUnits].map((unit) {
                  final isSelected = _selectedDayUnits.contains(unit);
                  return FilterChip(
                    label: Text(unit),
                    selected: isSelected,
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selectedDayUnits.add(unit);
                        _dayFactorCtrl(unit);
                      } else {
                        _selectedDayUnits.remove(unit);
                      }
                    }),
                  );
                }).toList(),
              ),

              // Per-unit factor inputs for selected Day units
              if (_selectedDayUnits.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.secondaryContainer),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Day Unit Factors', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.secondary)),
                      const SizedBox(height: 12),
                      ..._selectedDayUnits.map((unit) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text(unit, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _dayFactorCtrl(unit),
                                decoration: const InputDecoration(
                                  labelText: 'Factor',
                                  prefixText: '× ',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // ── Optional Heat Matrix ──────────────────────────────────
              if (_requiresHeatDay) ...[
                Text('Heat Units (Optional)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Select units applicable when submitting heat readings', style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [...AppConstants.matrixUnits, ..._customUnits].map((unit) {
                    final isSelected = _selectedHeatUnits.contains(unit);
                    return FilterChip(
                      label: Text(unit),
                      selected: isSelected,
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _selectedHeatUnits.add(unit);
                          _heatFactorCtrl(unit);
                        } else {
                          _selectedHeatUnits.remove(unit);
                        }
                      }),
                    );
                  }).toList(),
                ),

                if (_selectedHeatUnits.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryContainer),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Heat Unit Factors', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary)),
                        const SizedBox(height: 12),
                        ..._selectedHeatUnits.map((unit) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: Text(unit, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _heatFactorCtrl(unit),
                                  decoration: const InputDecoration(
                                    labelText: 'Factor',
                                    prefixText: '× ',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],

              AppButton(
                label: 'Create Device',
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
