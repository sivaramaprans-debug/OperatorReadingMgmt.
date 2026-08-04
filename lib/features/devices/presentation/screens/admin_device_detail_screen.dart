import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../notifiers/device_assignments_notifier.dart';
import '../../../operators/presentation/notifiers/operators_list_notifier.dart';

class AdminDeviceDetailScreen extends ConsumerStatefulWidget {
  const AdminDeviceDetailScreen({super.key, required this.deviceId, this.device});
  final String deviceId;
  final SupabaseDevice? device;

  @override
  ConsumerState<AdminDeviceDetailScreen> createState() => _AdminDeviceDetailScreenState();
}

class _AdminDeviceDetailScreenState extends ConsumerState<AdminDeviceDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    if (device == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device Details')),
        body: const Center(child: Text('Device data missing')),
      );
    }

    final theme = Theme.of(context);
    final isActive = device.isActive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => context.push(
              RoutePaths.adminDeviceEdit.replaceFirst(':id', device.id),
              extra: device,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primaryContainer : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.settings_input_component_rounded,
                size: 48,
                color: isActive ? AppColors.primary : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              device.name,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Factor: ${device.multiplicationFactor.toStringAsFixed(3)}',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Chip(
              label: Text(isActive ? 'Active' : 'Inactive'),
              backgroundColor: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              labelStyle: TextStyle(
                color: isActive ? Colors.green.shade700 : Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide.none,
            ),
            
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            _buildDetailRow(context, Icons.calendar_today_rounded, 'Created', 
                DateTime.fromMillisecondsSinceEpoch(device.createdAt, isUtc: true).toLocal().toString().split('.')[0]),

            const SizedBox(height: 16),
            
            // Matrix Units
            _buildDetailRow(context, Icons.grid_view_rounded, 'Heat/Day Entry',
                device.requiresHeatDay ? 'Enabled' : 'Disabled'),
            const SizedBox(height: 16),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(device.requiresHeatDay ? 'Heat Units' : 'Matrix Units', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Builder(builder: (context) {
                Map<String, dynamic> heatFactors = {};
                try { heatFactors = jsonDecode(device.heatUnitFactors) as Map<String, dynamic>; } catch (_) {}
                return device.matrix.isEmpty
                    ? Text('No units assigned', style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant))
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: device.matrix
                            .split(',')
                            .map((u) => u.trim())
                            .where((u) => u.isNotEmpty)
                            .map((u) {
                              final f = heatFactors[u];
                              final label = f != null ? '$u  ×${(f as num).toStringAsFixed(1)}' : u;
                              return Chip(
                                label: Text(label),
                                backgroundColor: AppColors.primaryContainer,
                                labelStyle: const TextStyle(color: Color(0xFF001E3F), fontWeight: FontWeight.w600),
                                side: BorderSide.none,
                              );
                            })
                            .toList(),
                      );
              }),
            ),
            if (device.requiresHeatDay) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Day Units', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Builder(builder: (context) {
                  Map<String, dynamic> dayFactors = {};
                  try { dayFactors = jsonDecode(device.dayUnitFactors) as Map<String, dynamic>; } catch (_) {}
                  return device.dayMatrix.isEmpty
                      ? Text('No units assigned', style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: device.dayMatrix
                              .split(',')
                              .map((u) => u.trim())
                              .where((u) => u.isNotEmpty)
                              .map((u) {
                                final f = dayFactors[u];
                                final label = f != null ? '$u  ×${(f as num).toStringAsFixed(1)}' : u;
                                return Chip(
                                  label: Text(label),
                                  backgroundColor: AppColors.secondaryContainer,
                                  labelStyle: const TextStyle(color: Color(0xFF00201D), fontWeight: FontWeight.w600),
                                  side: BorderSide.none,
                                );
                              })
                              .toList(),
                        );
                }),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Assigned Operators', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 12),
            
            // To properly manage assignments from the device page, we would need 
            // a provider that gets assignments FOR a device.
            // For now, in a robust system, we manage assignments mainly from the operator profile,
            // or we add a specific query. Let's show a placeholder or a simple list if we had the query.
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Device assignment management is typically handled from the Operator profile. We can add specific device-centric assignment queries here later.'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
