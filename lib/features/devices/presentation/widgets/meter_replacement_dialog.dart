import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../../../core/utils/reading_calculation_utils.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../database/repositories/supabase_meter_replacement_repository.dart';
import '../../../../database/supabase_providers.dart';

class MeterReplacementDialog extends ConsumerStatefulWidget {
  const MeterReplacementDialog({
    super.key,
    required this.device,
    this.latestReadingValues,
  });

  final SupabaseDevice device;
  final Map<String, double>? latestReadingValues;

  @override
  ConsumerState<MeterReplacementDialog> createState() => _MeterReplacementDialogState();
}

class _MeterReplacementDialogState extends ConsumerState<MeterReplacementDialog> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  final _notesController = TextEditingController();

  final Map<String, TextEditingController> _oldFinalControllers = {};
  final Map<String, TextEditingController> _oldFactorControllers = {};
  final Map<String, TextEditingController> _newInitialControllers = {};
  final Map<String, TextEditingController> _newFactorControllers = {};

  bool _isSaving = false;
  late List<String> _units;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = now;
    _selectedTime = TimeOfDay.fromDateTime(now);

    final d = widget.device;
    final heatUnits = d.matrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final dayUnits = d.dayMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    _units = {...heatUnits, ...dayUnits}.toList();
    if (_units.isEmpty) {
      _units = ['KWH', 'KWHLT'];
    }

    final activeHeatFactors = ReadingCalculationUtils.parseFactors(d.heatUnitFactors);
    final activeDayFactors = ReadingCalculationUtils.parseFactors(d.dayUnitFactors);

    for (final u in _units) {
      final latestVal = widget.latestReadingValues?[u] ?? 0.0;
      _oldFinalControllers[u] = TextEditingController(text: latestVal > 0 ? latestVal.toStringAsFixed(2) : '');
      
      final activeMf = activeHeatFactors[u] ?? activeDayFactors[u] ?? d.multiplicationFactor;
      _oldFactorControllers[u] = TextEditingController(text: activeMf.toString());
      _newInitialControllers[u] = TextEditingController(text: '0.00');
      _newFactorControllers[u] = TextEditingController(text: activeMf.toString());
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final c in _oldFinalControllers.values) c.dispose();
    for (final c in _oldFactorControllers.values) c.dispose();
    for (final c in _newInitialControllers.values) c.dispose();
    for (final c in _newFactorControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      final repDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final repMs = repDateTime.millisecondsSinceEpoch;

      final oldFinalMap = <String, double>{};
      final oldFactorMap = <String, double>{};
      final newInitialMap = <String, double>{};
      final newFactorMap = <String, double>{};

      for (final u in _units) {
        oldFinalMap[u] = double.tryParse(_oldFinalControllers[u]?.text ?? '0') ?? 0.0;
        oldFactorMap[u] = double.tryParse(_oldFactorControllers[u]?.text ?? '1') ?? 1.0;
        newInitialMap[u] = double.tryParse(_newInitialControllers[u]?.text ?? '0') ?? 0.0;
        newFactorMap[u] = double.tryParse(_newFactorControllers[u]?.text ?? '1') ?? 1.0;
      }

      // 1. Record Meter Replacement Event
      final repo = SupabaseMeterReplacementRepository();
      await repo.recordReplacement(
        deviceId: widget.device.id,
        replacementDate: repMs,
        oldFinalValues: oldFinalMap,
        oldFactors: oldFactorMap,
        newInitialValues: newInitialMap,
        newFactors: newFactorMap,
        notes: _notesController.text.trim(),
      );

      // 2. Update active factors in device
      final devRepo = ref.read(supabaseDevicesRepoProvider);
      await devRepo.update(
        widget.device.id,
        name: widget.device.name,
        multiplicationFactor: newFactorMap['KWH'] ?? widget.device.multiplicationFactor,
        matrix: widget.device.matrix,
        dayMatrix: widget.device.dayMatrix,
        requiresHeatDay: widget.device.requiresHeatDay,
        heatUnitFactors: jsonEncode(newFactorMap),
        dayUnitFactors: jsonEncode(newFactorMap),
      );

      ref.invalidate(allDevicesSupabaseProvider);
      ref.invalidate(activeDevicesSupabaseProvider);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Meter replacement & new factors recorded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Replace Meter / New MF', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        Text('Device: ${widget.device.name}', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),

              Expanded(
                child: ListView(
                  children: [
                    // Changeover Date & Time Picker
                    Text('1. Date & Time of Replacement', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today_rounded, size: 16),
                            label: Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => _selectedDate = picked);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time_rounded, size: 16),
                            label: Text(_selectedTime.format(context)),
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

                    // Old Meter Final Readings & Factors
                    Text('2. Old Meter Final Readings & MF', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                    const SizedBox(height: 4),
                    Text('Final reading values when the old meter was uninstalled:', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    ..._units.map((u) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 60, child: Text(u, style: const TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _oldFinalControllers[u],
                              decoration: InputDecoration(
                                labelText: 'Old Final ($u)',
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _oldFactorControllers[u],
                              decoration: InputDecoration(
                                labelText: 'Old MF',
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 16),

                    // New Meter Initial Readings & Factors
                    Text('3. New Meter Initial Readings & New MF', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                    const SizedBox(height: 4),
                    Text('Starting baseline of new meter (e.g. 0.00) & new multiplication factor:', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    ..._units.map((u) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 60, child: Text(u, style: const TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _newInitialControllers[u],
                              decoration: InputDecoration(
                                labelText: 'New Start ($u)',
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _newFactorControllers[u],
                              decoration: InputDecoration(
                                labelText: 'New MF',
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 16),

                    // Notes
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Reason / Notes (Optional)',
                        hintText: 'e.g. Meter replaced due to CT upgrade from 400/5 to 800/5',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_rounded),
                    label: const Text('Save Replacement'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _isSaving ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
