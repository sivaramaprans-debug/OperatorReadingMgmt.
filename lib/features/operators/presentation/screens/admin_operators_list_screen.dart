import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/error_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../notifiers/operators_list_notifier.dart';

class AdminOperatorsListScreen extends ConsumerWidget {
  const AdminOperatorsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operatorsAsync = ref.watch(operatorsListProvider);
    final theme = Theme.of(context);

    // Listen to status toggle changes
    ref.listen(operatorsListNotifierProvider, (prev, next) {
      if (next is AsyncError) {
        SnackbarHelper.showError(context, next.error.toString());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operators'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go(RoutePaths.adminDashboard),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(RoutePaths.adminOperatorCreate),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: operatorsAsync.when(
        loading: () => const LoadingWidget(message: 'Loading operators...'),
        error: (err, stack) => ErrorStateWidget(
          message: 'Failed to load operators',
          onRetry: () => ref.invalidate(operatorsListProvider),
        ),
        data: (operators) {
          if (operators.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.people_outline_rounded,
              title: 'No Operators Found',
              subtitle: 'Add a new operator to get started.',
              actionLabel: 'Add Operator',
              action: () => context.push(RoutePaths.adminOperatorCreate),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: operators.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final op = operators[index];
              final isActive = op.isActive;
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
                    RoutePaths.adminOperatorDetail.replaceFirst(':id', op.id),
                    extra: op,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: isActive
                              ? AppColors.primaryContainer
                              : Colors.grey.shade300,
                          foregroundColor: isActive
                              ? AppColors.primary
                              : Colors.grey.shade600,
                          child: Text(
                            op.fullName.isNotEmpty
                                ? op.fullName.substring(0, 1).toUpperCase()
                                : '?',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                op.fullName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isActive ? null : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '@${op.username}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isActive 
                                      ? theme.colorScheme.onSurfaceVariant
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isActive,
                          onChanged: (val) async {
                            final success = await ref
                                .read(operatorsListNotifierProvider.notifier)
                                .toggleStatus(op.id, val);
                            if (success && context.mounted) {
                              SnackbarHelper.showSuccess(
                                context,
                                'Operator ${val ? 'activated' : 'deactivated'}',
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
