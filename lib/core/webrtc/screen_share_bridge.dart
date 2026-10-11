import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Android needs a "sharing" foreground service before the screen can be
/// captured. This asks permission and starts / stops that service.
class ScreenShareBridge {
  static const _ch = MethodChannel('qt/pip');
  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// False if the user refused the permission.
  static Future<bool> begin() async {
    if (!_android) return true;
    try {
      final ok = await Helper.requestCapturePermission();
      if (!ok) return false;
      await _ch.invokeMethod('shareOn');
      return true;
    } catch (e) {
      debugPrint('SHARE: begin failed: $e');
      return false;
    }
  }

  static Future<void> end() async {
    if (!_android) return;
    try {
      await _ch.invokeMethod('shareOff');
    } catch (_) {}
  }
}