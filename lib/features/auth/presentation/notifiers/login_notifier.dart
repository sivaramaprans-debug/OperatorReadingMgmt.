import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local form state for the Login screen.
/// Holds per-field values and error messages.
class LoginFormState {
  const LoginFormState({
    this.username = '',
    this.password = '',
    this.usernameError,
    this.passwordError,
    this.isLoading = false,
    this.globalError,
    this.obscurePassword = true,
  });

  final String username;
  final String password;
  final String? usernameError;
  final String? passwordError;
  final bool isLoading;
  final String? globalError;
  final bool obscurePassword;

  bool get isValid =>
      usernameError == null && passwordError == null && username.isNotEmpty;

  LoginFormState copyWith({
    String? username,
    String? password,
    Object? usernameError = _sentinel,
    Object? passwordError = _sentinel,
    bool? isLoading,
    Object? globalError = _sentinel,
    bool? obscurePassword,
  }) =>
      LoginFormState(
        username: username ?? this.username,
        password: password ?? this.password,
        usernameError: usernameError == _sentinel
            ? this.usernameError
            : usernameError as String?,
        passwordError: passwordError == _sentinel
            ? this.passwordError
            : passwordError as String?,
        isLoading: isLoading ?? this.isLoading,
        globalError:
            globalError == _sentinel ? this.globalError : globalError as String?,
        obscurePassword: obscurePassword ?? this.obscurePassword,
      );
}

const _sentinel = Object();

class LoginNotifier extends Notifier<LoginFormState> {
  @override
  LoginFormState build() => const LoginFormState();

  void setUsername(String value) {
    state = state.copyWith(username: value, usernameError: null, globalError: null);
  }

  void setPassword(String value) {
    state = state.copyWith(password: value, passwordError: null, globalError: null);
  }

  void togglePasswordVisibility() {
    state = state.copyWith(obscurePassword: !state.obscurePassword);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setGlobalError(String? error) {
    state = state.copyWith(
        globalError: error, isLoading: false);
  }

  void clearErrors() {
    state = state.copyWith(
      usernameError: null,
      passwordError: null,
      globalError: null,
    );
  }

  /// Validates form client-side before calling auth.
  bool validate() {
    bool valid = true;
    String? usernameError;
    String? passwordError;

    if (state.username.trim().isEmpty) {
      usernameError = 'Username is required.';
      valid = false;
    }
    if (state.password.isEmpty) {
      passwordError = 'Password is required.';
      valid = false;
    }
    state = state.copyWith(
      usernameError: usernameError,
      passwordError: passwordError,
    );
    return valid;
  }
}

final loginNotifierProvider =
    NotifierProvider<LoginNotifier, LoginFormState>(LoginNotifier.new);
