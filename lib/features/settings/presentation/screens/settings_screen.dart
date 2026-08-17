import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../routing/route_paths.dart';
import '../../../../services/app_update_service.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../../auth/domain/entities/app_user.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isCheckingUpdates = false;

  Future<void> _manualCheckUpdates() async {
    setState(() => _isCheckingUpdates = true);
    final updateService = ref.read(appUpdateServiceProvider);
    final info = await updateService.checkForUpdates();
    setState(() => _isCheckingUpdates = false);

    if (!mounted) return;

    if (info == null) {
      SnackbarHelper.showError(context, 'Failed to check for updates. Please try again.');
      return;
    }

    if (info.hasUpdate) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Update Available!'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Version: v${info.latestVersion}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(info.releaseNotes),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                updateService.launchApkDownload(info.apkUrl);
              },
              child: const Text('Download APK'),
            ),
          ],
        ),
      );
    } else {
      SnackbarHelper.showSuccess(context, 'Your app is already up to date! (v${AppUpdateService.currentVersion})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = ref.watch(themeModeProvider);
    final user = ref.watch(authNotifierProvider.notifier).currentUser;
    final updateAsync = ref.watch(appUpdateCheckProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Theme Settings Card ─────────────────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('App Appearance', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Choose how the application theme looks on your device.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.phone_android_rounded),
                      ),
                    ],
                    selected: {currentTheme},
                    onSelectionChanged: (selectedSet) {
                      if (selectedSet.isNotEmpty) {
                        ref.read(themeModeProvider.notifier).setThemeMode(selectedSet.first);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── App Updates Card ───────────────────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('App Version & Updates', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Current Installed Version', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('v${AppUpdateService.currentVersion}'),
                    trailing: _isCheckingUpdates
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton.icon(
                            onPressed: _manualCheckUpdates,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Check Now'),
                          ),
                  ),
                  const Divider(),
                  updateAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                    error: (err, _) => Text('Error checking updates: $err', style: const TextStyle(color: Colors.red, fontSize: 11)),
                    data: (info) {
                      if (info != null && info.hasUpdate) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Update Available: v${info.latestVersion}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                info.releaseNotes,
                                style: const TextStyle(fontSize: 11, color: Colors.black87),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    ref.read(appUpdateServiceProvider).launchApkDownload(info.apkUrl);
                                  },
                                  icon: const Icon(Icons.download_rounded),
                                  label: const Text('Download & Update Now'),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 16, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          Text('App is up to date.', style: TextStyle(color: Colors.green.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Account Info Card ──────────────────────────────────────────────
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_circle_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Account Information', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Builder(builder: (context) {
                    final name = user is OperatorUser ? user.fullName : (user?.username ?? 'User');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(user?.username.substring(0, 1).toUpperCase() ?? 'U'),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Role: ${user?.role.toUpperCase() ?? 'OPERATOR'}'),
                    );
                  }),
                  const Divider(),
                  if (user?.role == 'operator') ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_outline_rounded),
                      title: const Text('Change Password'),
                      subtitle: const Text('Update your login password'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        context.push(RoutePaths.operatorChangePassword);
                      },
                    ),
                    const Divider(),
                  ],
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Logout',
                    onPressed: () {
                      ref.read(authNotifierProvider.notifier).logout();
                    },
                    variant: AppButtonVariant.danger,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
