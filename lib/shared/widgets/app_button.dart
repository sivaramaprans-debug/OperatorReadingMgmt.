import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Variant of the reusable button.
enum AppButtonVariant { primary, secondary, danger, ghost }

/// A premium-styled button with loading state and 48dp minimum tap target.
/// Uses the theme's ElevatedButton / OutlinedButton styling as a base,
/// with per-variant overrides.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.leadingIcon,
    this.trailingIcon,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = _buildChild(theme);
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 48,
      child: _buildButton(context, theme, child),
    );
  }

  Widget _buildChild(ThemeData theme) {
    if (isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: _spinnerColor(theme),
        ),
      );
    }
    final iconColor = _iconColor(theme);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingIcon != null) ...
          [Icon(leadingIcon, size: 18, color: iconColor), const SizedBox(width: 8)],
        Text(label),
        if (trailingIcon != null) ...
          [const SizedBox(width: 8), Icon(trailingIcon, size: 18, color: iconColor)],
      ],
    );
  }

  Widget _buildButton(BuildContext context, ThemeData theme, Widget child) {
    switch (variant) {
      case AppButtonVariant.primary:
        return ElevatedButton(onPressed: isLoading ? null : onPressed, child: child);
      case AppButtonVariant.secondary:
        return OutlinedButton(onPressed: isLoading ? null : onPressed, child: child);
      case AppButtonVariant.danger:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          child: child,
        );
      case AppButtonVariant.ghost:
        return TextButton(onPressed: isLoading ? null : onPressed, child: child);
    }
  }

  Color _spinnerColor(ThemeData theme) {
    switch (variant) {
      case AppButtonVariant.primary:
        return Colors.white;
      case AppButtonVariant.secondary:
        return theme.colorScheme.primary;
      case AppButtonVariant.danger:
        return Colors.white;
      case AppButtonVariant.ghost:
        return theme.colorScheme.primary;
    }
  }

  Color _iconColor(ThemeData theme) => _spinnerColor(theme);
}
