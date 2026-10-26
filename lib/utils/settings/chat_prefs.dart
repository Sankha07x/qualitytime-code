import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mute and lock settings per chat. Keys: 'u:<uid>' (friend), 'g:<id>' (group).
class ChatPrefs {
  ChatPrefs._();

  static final muted = ValueNotifier<Set<String>>(<String>{});
  static final locked = ValueNotifier<Set<String>>(<String>{});
  static String? _salt;
  static String? _hash;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      muted.value = (p.getStringList('muted_chats') ?? <String>[]).toSet();
      locked.value = (p.getStringList('locked_chats') ?? <String>[]).toSet();
      _salt = p.getString('chat_pin_salt');
      _hash = p.getString('chat_pin_hash');
    } catch (e) {
      debugPrint('ChatPrefs load failed: $e');
    }
  }

  static Future<void> setMuted(String key, bool on) async {
    final s = {...muted.value};
    if (on) {
      s.add(key);
    } else {
      s.remove(key);
    }
    muted.value = s;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('muted_chats', s.toList());
    } catch (_) {}
  }

  static Future<void> setLocked(String key, bool on) async {
    final s = {...locked.value};
    if (on) {
      s.add(key);
    } else {
      s.remove(key);
    }
    locked.value = s;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('locked_chats', s.toList());
    } catch (_) {}
  }

  static bool get hasPin => _hash != null && _salt != null;

  static String _h(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<void> setPin(String pin) async {
    final r = Random.secure();
    final salt =
        base64Url.encode(List<int>.generate(12, (_) => r.nextInt(256)));
    _salt = salt;
    _hash = _h(salt, pin);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('chat_pin_salt', salt);
      await p.setString('chat_pin_hash', _hash!);
    } catch (_) {}
  }

  static bool checkPin(String pin) =>
      hasPin && _h(_salt!, pin) == _hash;
}