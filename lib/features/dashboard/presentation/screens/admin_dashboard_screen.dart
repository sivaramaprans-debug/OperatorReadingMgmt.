import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/app_update_banner.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../notifiers/admin_dashboard_notifier.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminDashboardStatsProvider);
    final theme = Theme.of(context);
    final admin = ref.watch(authNotifierProvider.notifier).currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_rounded),
            tooltip: 'Check for Updates',
            onPressed: () async {
              final url = Uri.parse('https://github.com/sivaramaprans-debug/OperatorReadingMgmt./releases/latest');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminDashboardStatsProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppUpdateBanner(),
              Card(
                color: AppColors.primaryContainer.withOpacity(0.4),
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 32),
                  title: const Text('Check for App Updates', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Tap to open GitHub Releases and download latest APK'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () async {
                    final url = Uri.parse('https://github.com/sivaramaprans-debug/OperatorReadingMgmt./releases/latest');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ),
              Text(
                'Welcome, ${admin?.username ?? 'Admin'}',
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
                          title: 'Operators',
                          value: stats.totalOperators.toString(),
                          icon: Icons.people_alt_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          title: 'Devices',
                          value: stats.activeDevices.toString(),
                          icon: Icons.settings_input_component_rounded,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          title: 'Readings Today',
                          value: stats.todayReadings.toString(),
                          icon: Icons.analytics_rounded,
                          color: AppColors.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 48),
              Text('Quick Actions', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2.5,
                children: [
                  _ActionCard(
                    title: 'Manage Operators',
                    icon: Icons.badge_rounded,
                    onTap: () => context.push(RoutePaths.adminOperators),
                  ),
                  _ActionCard(
                    title: 'Manage Devices',
                    icon: Icons.precision_manufacturing_rounded,
                    onTap: () => context.push(RoutePaths.adminDevices),
                  ),
                  _ActionCard(
                    title: 'View All Readings',
                    icon: Icons.list_alt_rounded,
                    onTap: () => context.push(RoutePaths.adminReadings),
                  ),
                  _ActionCard(
                    title: 'Audit Logs',
                    icon: Icons.security_rounded,
                    onTap: () => context.push(RoutePaths.adminAuditLogs),
                  ),
                  _ActionCard(
                    title: 'Dedusting Sheet',
                    icon: Icons.air_rounded,
                    color: AppColors.secondary,
                    onTap: () => context.push(RoutePaths.adminDeddustingReadings),
                  ),
                  _ActionCard(
                    title: 'Water Meter Sheet',
                    icon: Icons.water_drop_rounded,
                    color: Colors.blue,
                    onTap: () => context.push(RoutePaths.adminWaterReadings),
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
          Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.title, required this.icon, required this.onTap, this.color});
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }
}
