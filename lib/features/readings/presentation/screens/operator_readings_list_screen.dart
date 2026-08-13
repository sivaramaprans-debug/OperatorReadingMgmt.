import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../notifiers/operator_readings_notifier.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../widgets/readings_calculated_table.dart';

class OperatorReadingsListScreen extends ConsumerWidget {
  const OperatorReadingsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final operator = ref.watch(authNotifierProvider.notifier).currentUser;
    final devicesAsync = ref.watch(assignedActiveDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Readings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_rounded),
            tooltip: 'Check for Updates',
            onPressed: () async {
              final url = Uri.parse('https://github.com/sivaramaprans-debug/OperatorReadingMgmt./releases/latest');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not launch update page.')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.operatorReadingAdd),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Reading'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Operator welcome header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: AppColors.primaryContainer.withOpacity(0.3),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  child: Text(operator?.username.substring(0, 1).toUpperCase() ?? 'O'),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back,', style: theme.textTheme.bodySmall),
                      Text(
                        operator?.username ?? 'Operator',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Per-device reading tables
          Expanded(
            child: devicesAsync.when(
              loading: () => const LoadingWidget(message: 'Loading devices...'),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (devices) {
                if (devices.isEmpty) {
                  return EmptyStateWidget(
                    icon: Icons.devices_other_rounded,
                    title: 'No Devices Assigned',
                    subtitle: 'Contact your administrator to get devices assigned to you.',
                    actionLabel: 'Refresh',
                    action: () => ref.invalidate(assignedActiveDevicesProvider),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ...devices.map((device) => _DeviceReadingsSection(device: device)),
                    const SizedBox(height: 80), // space for FAB
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A section showing readings for one specific device as a DataTable.
class _DeviceReadingsSection extends ConsumerStatefulWidget {
  const _DeviceReadingsSection({required this.device});
  final SupabaseDevice device;

  @override
  ConsumerState<_DeviceReadingsSection> createState() => _DeviceReadingsSectionState();
}

class _DeviceReadingsSectionState extends ConsumerState<_DeviceReadingsSection> {
  String? _selectedType;

  @override
  Widget build(BuildContext context) {
    final readingsAsync = ref.watch(operatorReadingsForDeviceProvider(widget.device.id));
    final theme = Theme.of(context);

    final heatUnits = widget.device.matrix.isEmpty
        ? <String>[]
        : widget.device.matrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final dayUnits = widget.device.dayMatrix.isEmpty
        ? <String>[]
        : widget.device.dayMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final allUnits = {...heatUnits, ...dayUnits}.toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Device header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.electric_meter_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.device.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.device.requiresHeatDay) ...[
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedType,
                        hint: const Text('All Types', style: TextStyle(fontSize: 12)),
                        icon: const Icon(Icons.arrow_drop_down, size: 16),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All Types', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'heat', child: Text('Heat', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'day', child: Text('Day', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'standard', child: Text('Standard', style: TextStyle(fontSize: 12))),
                        ],
                        onChanged: (val) => setState(() => _selectedType = val),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Matrix unit chips
          if (allUnits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 6,
                children: allUnits.map((u) => Chip(
                  label: Text(u, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList(),
              ),
            ),

          // Readings DataTable
          readingsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error loading readings: $e'),
            ),
            data: (readings) {
              // Apply filter
              var filtered = readings;
              if (_selectedType != null) {
                filtered = readings.where((r) => r.readingType == _selectedType).toList();
              }

              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No readings found.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                );
              }

              final heatFactors = parseFactorMap(widget.device.heatUnitFactors);
              final dayFactors = parseFactorMap(widget.device.dayUnitFactors);

              return ReadingsCalculatedTable(
                readings: filtered,
                matrixUnits: allUnits,
                showTypeColumn: widget.device.requiresHeatDay,
                heatUnitFactors: heatFactors,
                dayUnitFactors: dayFactors,
              );
            },
          ),
        ],
      ),
    );
  }
}
