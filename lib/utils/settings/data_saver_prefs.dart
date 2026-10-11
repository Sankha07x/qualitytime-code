import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether calls should start on Low quality.
class DataSaverPrefs {
  static const _key = 'data_saver_default';

  static Future<bool> isOn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setOn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}