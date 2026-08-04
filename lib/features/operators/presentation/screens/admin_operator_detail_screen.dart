import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../notifiers/operator_form_notifier.dart';

class AdminOperatorDetailScreen extends ConsumerStatefulWidget {
  const AdminOperatorDetailScreen({super.key, required this.operatorId, this.operator});

  final String operatorId;
  final SupabaseOperator? operator; // passed from list to avoid initial fetch if possible

  @override
  ConsumerState<AdminOperatorDetailScreen> createState() => _AdminOperatorDetailScreenState();
}

class _AdminOperatorDetailScreenState extends ConsumerState<AdminOperatorDetailScreen> {
  final _passwordController = TextEditingController();
  
  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _showResetPasswordDialog(BuildContext context) {
    _passwordController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a new password for this operator.'),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'New Password',
                hintText: 'Min 8 chars, 1 letter, 1 number',
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPass = _passwordController.text;
              Navigator.pop(context); // close dialog
              final success = await ref
                  .read(operatorFormNotifierProvider.notifier)
                  .resetPassword(widget.operatorId, newPass);
              if (success && mounted) {
                SnackbarHelper.showSuccess(context, 'Password reset successfully');
              } else if (mounted) {
                final err = ref.read(operatorFormNotifierProvider).error;
                SnackbarHelper.showError(context, err ?? 'Failed to reset password');
              }
            },
            child: const Text('Reset Password'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // In a real app, we'd watch a provider for a single operator by ID to react to edits.
    // For now, if we have it passed in extra, we just display it.
    // If not, we could fetch it, but GoRouter extra usually handles it.
    final op = widget.operator;
    if (op == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Operator Details')),
        body: const Center(child: Text('Operator data missing')),
      );
    }

    final theme = Theme.of(context);
    final isActive = op.isActive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operator Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => context.push(
              RoutePaths.adminOperatorEdit.replaceFirst(':id', op.id),
              extra: op,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: isActive ? AppColors.primaryContainer : Colors.grey.shade300,
              foregroundColor: isActive ? AppColors.primary : Colors.grey.shade600,
              child: Text(
                op.fullName.isNotEmpty ? op.fullName.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              op.fullName,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '@${op.username}',
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
                DateTime.fromMillisecondsSinceEpoch(op.createdAt, isUtc: true).toLocal().toString().split('.')[0]),

            const SizedBox(height: 40),

            AppButton(
              label: 'Reset Password',
              leadingIcon: Icons.lock_reset_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () => _showResetPasswordDialog(context),
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
