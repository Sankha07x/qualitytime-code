import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../utils/settings/app_settings.dart';
import '../../utils/settings/fx_prefs.dart';

/// Sends the effects settings to the Android side. Never throws.
class FxBridge {
  static const _ch = MethodChannel('qt/pip');
  static String? _trackId;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> applyVideo({String? trackId}) async {
    if (!_android) return;
    if (trackId != null) _trackId = trackId;
    final id = _trackId;
    if (id == null) return;
    try {
      final p = await FxPrefs.load();
      await _ch.invokeMethod('fxVideo', {
        'trackId': id,
        'mode': p.bg.index,
        'denoise': p.denoise,
        'fast': p.fast,
        'bgPath': AppSettings.wallpaper.value ?? '',
      });
    } catch (e) {
      debugPrint('FX: applyVideo failed: $e');
    }
  }

  static Future<void> applyAudio() async {
    if (!_android) return;
    try {
      final p = await FxPrefs.load();
      await _ch.invokeMethod('fxAudio', p.noise);
    } catch (e) {
      debugPrint('FX: applyAudio failed: $e');
    }
  }

  static Future<void> clearVideo() async {
    _trackId = null;
    if (!_android) return;
    try {
      await _ch.invokeMethod('fxVideo', {
        'trackId': '',
        'mode': 0,
        'denoise': false,
        'fast': false,
        'bgPath': '',
      });
    } catch (_) {}
  }

  /// The phone turned the effects off by itself. Returns a message to show.
  static Future<String?> handleAutoOff(String why) async {
    final p = await FxPrefs.load();
    p.bg = BgMode.off;
    p.denoise = false;
    await p.save();
    switch (why) {
      case 'slow':
        return 'Video effects turned off: this phone is too slow for them.';
      case 'model':
        return 'Background effect is not available on this phone.';
      default:
        return 'Video effects turned off because of an error.';
    }
  }
}