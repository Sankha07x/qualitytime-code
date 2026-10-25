import 'package:flutter/services.dart' as s;
import 'settings/app_settings.dart';

/// Vibration helper. Everything obeys the one Vibration switch in Settings.
class Haptics {
  Haptics._();
  static bool get _on => AppSettings.vibration.value;
  static void tap() {
    if (_on) s.HapticFeedback.selectionClick();
  }

  static void light() {
    if (_on) s.HapticFeedback.lightImpact();
  }

  static void medium() {
    if (_on) s.HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (_on) s.HapticFeedback.heavyImpact();
  }
}

/// Same name as Flutter's class. A file that imports this (and hides
/// Flutter's) obeys the Settings switch with no other code changes.
class HapticFeedback {
  HapticFeedback._();
  static Future<void> lightImpact() async => Haptics.light();
  static Future<void> mediumImpact() async => Haptics.medium();
  static Future<void> heavyImpact() async => Haptics.heavy();
  static Future<void> selectionClick() async => Haptics.tap();
}