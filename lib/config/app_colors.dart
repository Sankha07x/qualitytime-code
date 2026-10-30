import 'package:flutter/material.dart';
import '../utils/settings/app_settings.dart';

/// The QualityTime 6-color design palette (dark to light):
/// #051F20 screen background
/// #0B2B26 tiles (see-through) and bottom bar
/// #163832 open chat tile and own message bubbles
/// #235347 thin borders and dividers
/// #8EB69B call/video icons, send button, secondary text
/// #DAF1DE names and main text
class AppColors {
  AppColors._();

  static const Color c051F20 = Color(0xFF051F20);
  static const Color c0B2B26 = Color(0xFF0B2B26);
  static const Color c163832 = Color(0xFF163832);
  static const Color c235347 = Color(0xFF235347);
  static const Color c8EB69B = Color(0xFF8EB69B);
  static const Color cDAF1DE = Color(0xFFDAF1DE);

  /// Default accent value used in AppSettings.
  static const int defaultAccent = 0xFF009688;

  /// Whether the user has chosen a custom accent in settings.
  static bool hasCustomAccent() => AppSettings.accent.value != defaultAccent;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Screen background (#051F20 dark, #DAF1DE light flipped).
  static Color screenBackground(BuildContext context) {
    if (hasCustomAccent()) {
      return Theme.of(context).colorScheme.surface;
    }
    return isDark(context) ? c051F20 : cDAF1DE;
  }

  /// Tile soft translucent fill (#0B2B26 see-through).
  static Color tileFill(BuildContext context) {
    if (hasCustomAccent()) {
      return Theme.of(context).colorScheme.surface.withOpacity(0.45);
    }
    return isDark(context)
        ? c0B2B26.withOpacity(0.65)
        : Colors.white.withOpacity(0.65);
  }

  /// Open chat tile background (#163832).
  static Color openChatTile(BuildContext context) {
    if (hasCustomAccent()) {
      return Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5);
    }
    return isDark(context)
        ? c163832
        : Color(0xFFCBEAD2);
  }

  /// 1px light border (#235347 at low opacity).
  static Color tileBorder(BuildContext context) {
    if (hasCustomAccent()) {
      return Theme.of(context).colorScheme.outline.withOpacity(0.2);
    }
    return isDark(context)
        ? c235347.withOpacity(0.45)
        : c8EB69B.withOpacity(0.45);
  }

  /// Thin dividers (#235347).
  static Color divider(BuildContext context) {
    if (hasCustomAccent()) {
      return Theme.of(context).dividerColor;
    }
    return isDark(context) ? c235347 : c8EB69B.withOpacity(0.5);
  }

  /// Icons, send button, secondary text (#8EB69B).
  static Color accent(BuildContext context) {
    if (hasCustomAccent()) {
      return Color(AppSettings.accent.value);
    }
    return isDark(context) ? c8EB69B : c235347;
  }

  /// Names and main text (#DAF1DE dark, #051F20 light).
  static Color textMain(BuildContext context) {
    if (hasCustomAccent()) {
      return Theme.of(context).colorScheme.onSurface;
    }
    return isDark(context) ? cDAF1DE : c051F20;
  }

  /// Secondary text (#8EB69B dark, #235347 light).
  static Color textSecondary(BuildContext context) {
    if (hasCustomAccent()) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return isDark(context) ? c8EB69B : c235347;
  }

  /// My message bubble fill (#163832).
  static Color myBubble(BuildContext context) {
    if (hasCustomAccent()) {
      return Theme.of(context).colorScheme.primary;
    }
    return isDark(context) ? c163832 : c8EB69B;
  }

  /// Bottom bar background fill (#0B2B26 translucent).
  static Color bottomBar(BuildContext context) {
    if (hasCustomAccent()) {
      return Theme.of(context).colorScheme.surface.withOpacity(0.85);
    }
    return isDark(context)
        ? c0B2B26.withOpacity(0.85)
        : cDAF1DE.withOpacity(0.85);
  }
}
