import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/error_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../notifiers/devices_list_notifier.dart';

class AdminDevicesListScreen extends ConsumerWidget {
  const AdminDevicesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesListProvider);
    final theme = Theme.of(context);

    ref.listen(devicesListNotifierProvider, (prev, next) {
      if (next is AsyncError) {
        SnackbarHelper.showError(context, next.error.toString());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go(RoutePaths.adminDashboard),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(RoutePaths.adminDeviceCreate),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: devicesAsync.when(
        loading: () => const LoadingWidget(message: 'Loading devices...'),
        error: (err, stack) => ErrorStateWidget(
          message: 'Failed to load devices',
          onRetry: () => ref.invalidate(devicesListProvider),
        ),
        data: (devices) {
          if (devices.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.precision_manufacturing_rounded,
              title: 'No Devices Found',
              subtitle: 'Add a new device to get started.',
              actionLabel: 'Add Device',
              action: () => context.push(RoutePaths.adminDeviceCreate),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final device = devices[index];
              final isActive = device.isActive;
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isActive 
                        ? AppColors.primary.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.3),
                  ),
                ),
                color: isActive 
                    ? theme.colorScheme.surface
                    : theme.colorScheme.surfaceVariant.withOpacity(0.5),
                child: InkWell(
                  onTap: () => context.push(
                    RoutePaths.adminDeviceDetail.replaceFirst(':id', device.id),
                    extra: device,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.primaryContainer : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.settings_input_component_rounded,
                            color: isActive ? AppColors.primary : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isActive ? null : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Factor: ${device.multiplicationFactor.toStringAsFixed(3)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isActive 
                                      ? theme.colorScheme.onSurfaceVariant
                                      : Colors.grey,
                                ),
                              ),
                              if (device.matrix.isNotEmpty || device.dayMatrix.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    if (device.matrix.isNotEmpty)
                                      ...device.matrix.split(',').map((u) => u.trim()).where((u) => u.isNotEmpty).map((u) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: device.requiresHeatDay ? AppColors.tertiaryContainer : AppColors.primaryContainer,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(u, style: const TextStyle(fontSize: 10, color: Color(0xFF1A1C1E), fontWeight: FontWeight.w600)),
                                      )),
                                    if (device.requiresHeatDay && device.dayMatrix.isNotEmpty)
                                      ...device.dayMatrix.split(',').map((u) => u.trim()).where((u) => u.isNotEmpty).map((u) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.secondaryContainer,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(u, style: const TextStyle(fontSize: 10, color: Color(0xFF1A1C1E), fontWeight: FontWeight.w600)),
                                      )),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        Switch(
                          value: isActive,
                          onChanged: (val) async {
                            final success = await ref
                                .read(devicesListNotifierProvider.notifier)
                                .toggleStatus(device.id, val);
                            if (success && context.mounted) {
                              SnackbarHelper.showSuccess(
                                context,
                                'Device ${val ? 'activated' : 'deactivated'}',
                              );
                            }
                          },
                          activeColor: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
