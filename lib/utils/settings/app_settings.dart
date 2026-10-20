import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only look and sound settings. Nothing here is uploaded.
class AppSettings {
  AppSettings._();

  static const accents = <int>[
    0xFF009688, 0xFF2563EB, 0xFF7C3AED, 0xFFDB2777,
    0xFFEA580C, 0xFF16A34A, 0xFFDC2626, 0xFFCA8A04,
  ];

  static const tones = <String, String>{
    'classic': 'Classic beep',
    'chime': 'Chime',
    'marimba': 'Marimba',
    'digital': 'Digital',
    'pulse': 'Pulse',
    'bell': 'Bell',
    'soft': 'Soft',
  };

  static final accent = ValueNotifier<int>(0xFF009688);
  static final wallpaper = ValueNotifier<String?>(null);
  static final wallpaperOnCall = ValueNotifier<bool>(true);
  static final wallpaperBlur = ValueNotifier<bool>(false);
  static final tone = ValueNotifier<String>('classic');
  static final incomingTone = ValueNotifier<String>('system');
  static final holdTone = ValueNotifier<String>('soft');
  static String? customTonePath;
  static String? customToneName;
  static String? customIncomingPath;
  static String? customIncomingName;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      accent.value = p.getInt('set_accent') ?? accent.value;
      final wp = p.getString('set_wallpaper');
      wallpaper.value = (wp != null && File(wp).existsSync()) ? wp : null;
      wallpaperOnCall.value = p.getBool('set_wp_call') ?? true;
      wallpaperBlur.value = p.getBool('set_wp_blur') ?? false;
      final ct = p.getString('set_tone_custom');
      if (ct != null && File(ct).existsSync()) {
        customTonePath = ct;
        customToneName = p.getString('set_tone_name');
      }
      var t = p.getString('set_tone') ?? 'classic';
      if (t == 'custom' && customTonePath == null) t = 'classic';
      tone.value = t;
      final ci = p.getString('set_incoming_custom');
      if (ci != null && File(ci).existsSync()) {
        customIncomingPath = ci;
        customIncomingName = p.getString('set_incoming_name');
      }
      var it = p.getString('set_incoming_tone') ?? 'system';
      if (it == 'custom' && customIncomingPath == null) it = 'system';
      incomingTone.value = it;
      holdTone.value = p.getString('set_hold_tone') ?? 'soft';
    } catch (e) {
      debugPrint('Settings load failed: $e');
    }
  }

  static void _tryDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  static Future<void> setAccent(int c) async {
    accent.value = c;
    final p = await SharedPreferences.getInstance();
    await p.setInt('set_accent', c);
  }

  /// Returns an error text, or null (also null when the user cancels).
  static Future<String?> pickWallpaper() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (x == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await x.saveTo(dest);
    final old = wallpaper.value;
    wallpaper.value = dest;
    final p = await SharedPreferences.getInstance();
    await p.setString('set_wallpaper', dest);
    if (old != null) _tryDelete(old);
    return null;
  }
  
  static Future<void> setWallpaperOnCall(bool v) async {
    wallpaperOnCall.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('set_wp_call', v);
  }

  static Future<void> setWallpaperBlur(bool v) async {
    wallpaperBlur.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('set_wp_blur', v);
  }
  
  static Future<void> clearWallpaper() async {
    final old = wallpaper.value;
    wallpaper.value = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('set_wallpaper');
    if (old != null) _tryDelete(old);
  }

  static Future<void> setIncomingTone(String id) async {
    incomingTone.value = id;
    final p = await SharedPreferences.getInstance();
    await p.setString('set_incoming_tone', id);
  }

  static Future<void> setHoldTone(String id) async {
    holdTone.value = id;
    final p = await SharedPreferences.getInstance();
    await p.setString('set_hold_tone', id);
  }

  static Future<void> setTone(String id) async {
    tone.value = id;
    final p = await SharedPreferences.getInstance();
    await p.setString('set_tone', id);
  }

  /// Returns an error text, or null (also null when the user cancels).
  static Future<String?> pickCustomTone({bool incoming = false}) async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Audio',
        mimeTypes: ['audio/*'],
        extensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
      ),
    ]);
    if (f == null) return null;
    if (await f.length() > 10 * 1024 * 1024) {
      return 'That file is too big. Use one under 10 MB.';
    }
    final dir = await getApplicationDocumentsDirectory();
    final name = f.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'mp3';
    final dest =
        '${dir.path}/ringtone_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await f.saveTo(dest);
    final p = await SharedPreferences.getInstance();
    if (incoming) {
      final old = customIncomingPath;
      customIncomingPath = dest;
      customIncomingName = name;
      await p.setString('set_incoming_custom', dest);
      await p.setString('set_incoming_name', name);
      incomingTone.value = 'custom';
      await p.setString('set_incoming_tone', 'custom');
      if (old != null) _tryDelete(old);
    } else {
      final old = customTonePath;
      customTonePath = dest;
      customToneName = name;
      await p.setString('set_tone_custom', dest);
      await p.setString('set_tone_name', name);
      tone.value = 'custom';
      await p.setString('set_tone', 'custom');
      if (old != null) _tryDelete(old);
    }
    return null;
  }

  static Source sourceFor(String id) {
    if (id == 'custom' && customTonePath != null) {
      return DeviceFileSource(customTonePath!);
    }
    if (id == 'classic' || id == 'custom') {
      return AssetSource('sounds/ringback.wav');
    }
    return AssetSource('sounds/tone_$id.wav');
  }

  static Source ringbackSource() => sourceFor(tone.value);
  /// For the incoming screen (app open). Null = use the phone ringtone.
  static Source? incomingSource() {
    final id = incomingTone.value;
    if (id == 'system') return null;
    if (id == 'custom') {
      final p = customIncomingPath;
      return p == null ? null : DeviceFileSource(p);
    }
    return sourceFor(id);
  }
}