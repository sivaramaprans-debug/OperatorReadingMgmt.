import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../notifiers/operator_dashboard_notifier.dart';

import '../../../../shared/widgets/app_update_banner.dart';

class OperatorDashboardScreen extends ConsumerWidget {
  const OperatorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(operatorDashboardStatsProvider);
    final theme = Theme.of(context);
    final operatorUser = ref.watch(authNotifierProvider.notifier).currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operator Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(operatorDashboardStatsProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppUpdateBanner(),
              Text(
                'Welcome, ${operatorUser?.username ?? 'Operator'}',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: statsAsync.when(
                  loading: () => const LoadingWidget(),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (stats) => Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Assigned Devices',
                          value: stats.assignedDevices.toString(),
                          icon: Icons.precision_manufacturing_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          title: 'Readings Today',
                          value: stats.todayReadings.toString(),
                          icon: Icons.assignment_turned_in_rounded,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add New Reading'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(24),
                  textStyle: theme.textTheme.titleMedium,
                ),
                onPressed: () => context.push(RoutePaths.operatorReadingAdd),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.history_rounded),
                label: const Text('View My Past Readings'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(24),
                  textStyle: theme.textTheme.titleMedium,
                ),
                onPressed: () => context.push(RoutePaths.operatorReadings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
