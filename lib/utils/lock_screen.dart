import 'package:flutter/services.dart';

/// Lets the app show over the lock screen only while a call screen is open.
class LockScreen {
  static const _ch = MethodChannel('qt/pip');
  static int _n = 0;

  static void hold() {
    _n++;
    _send(true);
  }

  static void release() {
    if (_n > 0) _n--;
    if (_n == 0) _send(false);
  }

  static void _send(bool on) {
    _ch.invokeMethod('callUi', on).catchError((_) {});
  }
}