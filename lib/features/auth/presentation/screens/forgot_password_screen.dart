import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../routing/route_paths.dart';
import '../../../../services/secure_storage_service.dart';
import '../../../auth/data/repositories/auth_repository_impl.dart';
import '../../../auth/domain/usecases/admin_recovery_usecase.dart';
import '../notifiers/auth_notifier.dart';
import '../widgets/auth_text_field.dart';

/// Admin-only forgot password screen using local recovery code (§0.4a).
/// Operators have no self-service reset — Admin resets their password.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _codeError;
  String? _newPasswordError;
  String? _confirmError;
  String? _globalError;
  bool _success = false;

  @override
  void dispose() {
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _validate() {
    bool valid = true;
    setState(() {
      _codeError = _codeController.text.trim().isEmpty
          ? 'Recovery code is required.'
          : null;
      _newPasswordError = Validators.password(_newPasswordController.text);
      _confirmError = Validators.confirmPassword(
          _confirmController.text, _newPasswordController.text);
      if (_codeError != null || _newPasswordError != null || _confirmError != null) {
        valid = false;
      }
    });
    return valid;
  }

  Future<void> _onReset() async {
    if (!_validate()) return;
    setState(() {
      _isLoading = true;
      _globalError = null;
    });

    final repo = AuthRepositoryImpl(
      operatorsRepo: ref.read(supabaseOperatorsRepoProvider),
      secureStorage: ref.read(secureStorageProvider),
    );
    final useCase = ResetAdminPasswordWithRecoveryCodeUseCase(repo);
    final (success, failure) = await useCase(
      recoveryCode: _codeController.text.trim(),
      newPassword: _newPasswordController.text,
      confirmPassword: _confirmController.text,
    );

    setState(() {
      _isLoading = false;
      if (success) {
        _success = true;
      } else {
        _globalError = failure?.message ?? 'Password reset failed.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D2E5A),
              Color(0xFF1A6FBF),
              Color(0xFF006A60),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Back button row
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go(RoutePaths.login),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const Text(
                      'Admin Recovery',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                if (_success)
                  _buildSuccessState(context)
                else
                  _buildForm(),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: Colors.green, size: 44),
          ),
          const SizedBox(height: 20),
          const Text(
            'Password Reset!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your password has been updated. Please log in with your new password.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 14,
              fontFamily: 'Inter',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => context.go(RoutePaths.login),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Back to Login',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontFamily: 'Inter')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 40,
              offset: const Offset(0, 16)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reset Admin Password',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your recovery code and a new password.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 13,
                fontFamily: 'Inter'),
          ),
          const SizedBox(height: 24),

          AuthTextField(
            controller: _codeController,
            label: 'Recovery Code',
            hint: 'XXXX-XXXX',
            errorText: _codeError,
            prefixIcon: Icon(Icons.key_rounded,
                color: Colors.white.withOpacity(0.6), size: 20),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _codeError = null),
          ),
          const SizedBox(height: 20),

          AuthTextField(
            controller: _newPasswordController,
            label: 'New Password',
            hint: 'Min 8 chars, 1 letter + 1 number',
            errorText: _newPasswordError,
            obscureText: _obscureNew,
            textInputAction: TextInputAction.next,
            prefixIcon: Icon(Icons.lock_outline_rounded,
                color: Colors.white.withOpacity(0.6), size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureNew
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white.withOpacity(0.6),
                  size: 20),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
            onChanged: (_) => setState(() => _newPasswordError = null),
          ),
          const SizedBox(height: 20),

          AuthTextField(
            controller: _confirmController,
            label: 'Confirm New Password',
            hint: 'Re-enter new password',
            errorText: _confirmError,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            prefixIcon: Icon(Icons.lock_outline_rounded,
                color: Colors.white.withOpacity(0.6), size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white.withOpacity(0.6),
                  size: 20),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            onChanged: (_) => setState(() => _confirmError = null),
            onSubmitted: (_) => _onReset(),
          ),

          if (_globalError != null) ...
            [
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.red.withOpacity(0.35), width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: Colors.red.shade300, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _globalError!,
                        style: TextStyle(
                            color: Colors.red.shade300,
                            fontSize: 13,
                            fontFamily: 'Inter'),
                      ),
                    ),
                  ],
                ),
              ),
            ],

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _onReset,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary),
                    )
                  : const Text('Reset Password',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter')),
            ),
          ),
        ],
      ),
    );
  }
}
