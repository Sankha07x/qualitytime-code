import 'package:shared_preferences/shared_preferences.dart';

enum BgMode { off, blur, wallpaper }

/// Video and audio effects settings. Everything is OFF by default.
class FxPrefs {
  static const _kBg = 'fx_bg';
  static const _kDenoise = 'fx_denoise';
  static const _kFast = 'fx_fast';
  static const _kNoise = 'fx_noise';

  BgMode bg;
  bool denoise;
  bool fast;
  bool noise;

  FxPrefs({
    this.bg = BgMode.off,
    this.denoise = false,
    this.fast = false,
    this.noise = false,
  });

  static Future<FxPrefs> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final i = (p.getInt(_kBg) ?? 0).clamp(0, BgMode.values.length - 1);
      return FxPrefs(
        bg: BgMode.values[i],
        denoise: p.getBool(_kDenoise) ?? false,
        fast: p.getBool(_kFast) ?? false,
        noise: p.getBool(_kNoise) ?? false,
      );
    } catch (_) {
      return FxPrefs();
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kBg, bg.index);
      await p.setBool(_kDenoise, denoise);
      await p.setBool(_kFast, fast);
      await p.setBool(_kNoise, noise);
    } catch (_) {}
  }
}