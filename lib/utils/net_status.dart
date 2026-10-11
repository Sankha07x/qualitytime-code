import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

/// Simple online/offline detector (checks every 8 s).
class NetStatus {
  static final online = ValueNotifier<bool>(true);
  static Timer? _t;

  static void start() {
    if (kIsWeb) return;
    _check();
    _t ??= Timer.periodic(const Duration(seconds: 8), (_) => _check());
  }

  static Future<void> _check() async {
    try {
      final host = Uri.parse(AppConfig.supabaseUrl).host;
      final r = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 4));
      online.value = r.isNotEmpty;
    } catch (_) {
      online.value = false;
    }
  }
}