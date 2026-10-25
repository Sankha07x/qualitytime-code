import 'dart:ui' show FrameTiming;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'glass.dart';

/// Watches frame times. If a phone stays slow, glass blur is switched off.
class PerfGuard {
  PerfGuard._();
  static bool _started = false;
  static int _n = 0;
  static int _slow = 0;
  static int _bad = 0;

  static void start() {
    if (_started || kIsWeb) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> list) {
    if (!Glass.blurOn) return;
    for (final f in list) {
      _n++;
      if (f.totalSpan.inMilliseconds > 24) _slow++;
      if (_n >= 120) {
        _bad = _slow > 60 ? _bad + 1 : 0;
        _n = 0;
        _slow = 0;
        if (_bad >= 3) {
          Glass.blurOn = false;
          debugPrint('PERF: blur switched off (slow phone)');
        }
      }
    }
  }
}
