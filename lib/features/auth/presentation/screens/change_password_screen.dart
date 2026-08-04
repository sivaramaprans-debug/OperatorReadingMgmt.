import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/snackbar_helper.dart';
import '../notifiers/auth_notifier.dart';

/// Change Password screen for Operators (accessible from profile/settings).
/// Also usable by Admin from their profile.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState
    extends ConsumerState<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _currentError;
  String? _newError;
  String? _confirmError;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    bool valid = true;
    setState(() {
      _currentError = _currentController.text.isEmpty
          ? 'Current password is required.' : null;
      if (_newController.text.isEmpty) {
        _newError = 'New password is required.';
        valid = false;
      } else if (_newController.text.length < 8) {
        _newError = 'Min 8 characters.';
        valid = false;
      } else if (!RegExp(r'[a-zA-Z]').hasMatch(_newController.text)) {
        _newError = 'Must contain at least one letter.';
        valid = false;
      } else if (!RegExp(r'[0-9]').hasMatch(_newController.text)) {
        _newError = 'Must contain at least one number.';
        valid = false;
      } else {
        _newError = null;
      }
      if (_confirmController.text != _newController.text) {
        _confirmError = 'Passwords do not match.';
        valid = false;
      } else {
        _confirmError = null;
      }
      if (_currentError != null) valid = false;
    });
    if (!valid) return;

    setState(() => _isLoading = true);

    final user = ref.read(authNotifierProvider.notifier).currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final repo = ref.read(authRepositoryProvider);
    final (success, failure) = await repo.changePassword(
      userId: user.id,
      role: user.role,
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;
    if (success) {
      SnackbarHelper.showSuccess(
          context, 'Password changed successfully!');
      context.pop();
    } else {
      SnackbarHelper.showError(
          context, failure?.message ?? 'Password change failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info card
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'New password must be at least 8 characters with at least one letter and one number.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            _buildField(
              context,
              controller: _currentController,
              label: 'Current Password',
              errorText: _currentError,
              obscure: _obscureCurrent,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
              onChanged: (_) => setState(() => _currentError = null),
            ),
            const SizedBox(height: 16),

            _buildField(
              context,
              controller: _newController,
              label: 'New Password',
              errorText: _newError,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              onChanged: (_) => setState(() => _newError = null),
            ),
            const SizedBox(height: 16),

            _buildField(
              context,
              controller: _confirmController,
              label: 'Confirm New Password',
              errorText: _confirmError,
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              onChanged: (_) => setState(() => _confirmError = null),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _onSubmit(),
            ),

            const SizedBox(height: 32),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onSubmit,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white),
                      )
                    : const Text('Update Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? errorText,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
