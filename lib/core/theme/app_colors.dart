import 'package:flutter/material.dart';

// Material 3 color system for Operator Reading Management System.
// Primary palette: deep industrial blue-teal.
// Avoid generic red/green/blue — use curated HSL-tuned values.
abstract final class AppColors {
  // ── Brand / Primary ─────────────────────────────────────────────────────
  static const Color primary = Color(0xFF1A6FBF);      // Deep industrial blue
  static const Color primaryDark = Color(0xFF4DA3FF);   // Light-mode primary container / dark-mode primary
  static const Color primaryContainer = Color(0xFFD6E8FF); // Very light blue tint
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF001E3F);

  // ── Secondary ──────────────────────────────────────────────────────────
  static const Color secondary = Color(0xFF006A60);     // Deep teal
  static const Color secondaryContainer = Color(0xFFBFEDE7); // Teal tint
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF00201D);

  // ── Tertiary (accent) ─────────────────────────────────────────────────
  static const Color tertiary = Color(0xFFB25000);      // Amber-orange — status / warnings
  static const Color tertiaryContainer = Color(0xFFFFDCC8);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onTertiaryContainer = Color(0xFF3B1500);

  // ── Error ─────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFF410002);

  // ── Neutral / Surface (Light mode) ───────────────────────────────────────
  static const Color surface = Color(0xFFF6FAFE);       // Slightly blue-tinted white
  static const Color surfaceVariant = Color(0xFFDFE3EC);
  static const Color onSurface = Color(0xFF191C20);
  static const Color onSurfaceVariant = Color(0xFF43474E);
  static const Color outline = Color(0xFF73777F);
  static const Color outlineVariant = Color(0xFFC3C7CF);
  static const Color background = Color(0xFFF6FAFE);
  static const Color onBackground = Color(0xFF191C20);

  // ── Dark mode surfaces ────────────────────────────────────────────────────
  static const Color darkSurface = Color(0xFF0F1318);    // Near-black, blue undertone
  static const Color darkSurfaceVariant = Color(0xFF1E2328);
  static const Color darkSurfaceElevated = Color(0xFF252B32); // Cards in dark mode
  static const Color darkOnSurface = Color(0xFFF8FAFC);
  static const Color darkOnSurfaceVariant = Color(0xFFE2E8F0);

  // ── Semantic colours (used directly by widgets) ──────────────────────
  static const Color success = Color(0xFF1B6C41);        // Status: active / success
  static const Color successContainer = Color(0xFFB3F0CE);
  static const Color warning = Color(0xFFB25000);        // Status: warning / inactive
  static const Color warningContainer = Color(0xFFFFDCC8);
  static const Color info = Color(0xFF1A6FBF);

  // Status chip colours
  static const Color activeChip = Color(0xFF1B6C41);
  static const Color activeChipBg = Color(0xFFD0F4E1);
  static const Color inactiveChip = Color(0xFF8C4A00);
  static const Color inactiveChipBg = Color(0xFFFFEDD3);

  // Heat/Day reading type colours
  static const Color heatColor = Color(0xFFB25000);
  static const Color heatColorBg = Color(0xFFFFEDD3);
  static const Color dayColor = Color(0xFF1A6FBF);
  static const Color dayColorBg = Color(0xFFD6E8FF);
}
