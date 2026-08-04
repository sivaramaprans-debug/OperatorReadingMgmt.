import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../routing/route_paths.dart';
import '../notifiers/auth_notifier.dart';
import '../notifiers/login_notifier.dart';
import '../widgets/auth_text_field.dart';

/// Login screen — the main entry point.
/// Beautiful gradient + glassmorphism card design.
/// Handles both Admin and Operator login with a single form.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.sessionExpired = false});

  /// True when navigated here after a session timeout.
  final bool sessionExpired;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    final notifier = ref.read(loginNotifierProvider.notifier);
    if (!notifier.validate()) return;

    notifier.setLoading(true);
    final error = await ref.read(authNotifierProvider.notifier).login(
          _usernameController.text.trim(),
          _passwordController.text,
        );
    notifier.setLoading(false);

    if (error != null) {
      notifier.setGlobalError(error);
    }
    // Success: AuthNotifier state change triggers GoRouter redirect automatically
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(loginNotifierProvider);
    final authState = ref.watch(authNotifierProvider);
    final isExpired = authState is AuthSessionExpired || widget.sessionExpired;

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
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),

                    // ── Logo & title ───────────────────────────────────────
                    Hero(
                      tag: 'app_logo',
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.speed_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Operator Reading Mgmt',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to continue',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                        fontFamily: 'Inter',
                      ),
                    ),

                    // ── Session expired banner ─────────────────────────────
                    if (isExpired) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.amber.withOpacity(0.4), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.timer_off_rounded,
                                color: Colors.amber, size: 18),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Your session expired due to inactivity.',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 13,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),

                    // ── Glass card form ───────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Username
                          AuthTextField(
                            controller: _usernameController,
                            label: 'Username',
                            hint: 'Enter your username',
                            errorText: formState.usernameError,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            autofocus: true,
                            prefixIcon: Icon(
                              Icons.person_outline_rounded,
                              color: Colors.white.withOpacity(0.6),
                              size: 20,
                            ),
                            onChanged: (v) => ref
                                .read(loginNotifierProvider.notifier)
                                .setUsername(v),
                          ),
                          const SizedBox(height: 20),

                          // Password
                          AuthTextField(
                            controller: _passwordController,
                            label: 'Password',
                            hint: 'Enter your password',
                            errorText: formState.passwordError,
                            obscureText: formState.obscurePassword,
                            textInputAction: TextInputAction.done,
                            prefixIcon: Icon(
                              Icons.lock_outline_rounded,
                              color: Colors.white.withOpacity(0.6),
                              size: 20,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                formState.obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: Colors.white.withOpacity(0.6),
                                size: 20,
                              ),
                              onPressed: () => ref
                                  .read(loginNotifierProvider.notifier)
                                  .togglePasswordVisibility(),
                            ),
                            onChanged: (v) => ref
                                .read(loginNotifierProvider.notifier)
                                .setPassword(v),
                            onSubmitted: (_) => _onLogin(),
                          ),

                          // Global error
                          if (formState.globalError != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.35),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded,
                                      color: Colors.red.shade300, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      formState.globalError!,
                                      style: TextStyle(
                                        color: Colors.red.shade300,
                                        fontSize: 13,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 28),

                          // Login button
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: formState.isLoading ? null : _onLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: formState.isLoading
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : const Text(
                                      'Sign In',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Forgot password (Admin only) ───────────────────────
                    TextButton(
                      onPressed: () => context.go(RoutePaths.forgotPassword),
                      child: Text(
                        'Admin: Forgot Password?',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                          fontFamily: 'Inter',
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
