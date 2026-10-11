import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'update_dialog.dart';
import '../../features/call/active_call.dart';

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final List<String> notes;
  final double? sizeMb;
  final bool forced;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.notes,
    required this.sizeMb,
    required this.forced,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j, int current) {
    final min = (j['min_version_code'] as num?)?.toInt() ?? 0;
    return UpdateInfo(
      versionCode: (j['version_code'] as num).toInt(),
      versionName: (j['version_name'] ?? '').toString(),
      apkUrl: (j['apk_url'] ?? '').toString(),
      notes: [
        for (final n in (j['notes'] as List? ?? const [])) n.toString(),
      ],
      sizeMb: (j['size_mb'] as num?)?.toDouble(),
      forced: current < min,
    );
  }
}

/// Checks update.json on GitHub and shows the update pop-up.
class UpdateService with WidgetsBindingObserver {
  UpdateService._();
  static final instance = UpdateService._();

  /// Raw link of update.json in your GitHub repo.
  static const manifestUrl =
      'https://raw.githubusercontent.com/Sankha07x/qualitytime-releases/main/update.json';

  static const _every = Duration(minutes: 30);
  static const _snooze = Duration(hours: 6);
  static const _kSnooze = 'update_snooze_until';
  static const _kSnoozeCode = 'update_snooze_code';

  GlobalKey<NavigatorState>? _nav;
  Timer? _timer;
  Timer? _retry;
  bool _started = false;
  bool _showing = false;
  bool _dismissedSession = false;
  DateTime? _lastCheck;
  UpdateInfo? _pending;

  void start(GlobalKey<NavigatorState> nav) {
    if (_started || kIsWeb || !Platform.isAndroid) return;
    _started = true;
    _nav = nav;
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(seconds: 4), check);
    _timer = Timer.periodic(_every, (_) => check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last == null ||
        DateTime.now().difference(last) > const Duration(minutes: 10)) {
      check();
    } else {
      _tryShow();
    }
  }

  /// Version number after the "+" in pubspec (split-per-abi adds 1000s).
  Future<int> currentCode() async {
    final p = await PackageInfo.fromPlatform();
    return (int.tryParse(p.buildNumber) ?? 0) % 1000;
  }

  Future<Map<String, dynamic>?> _fetch() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(
          '$manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body);
      return j is Map<String, dynamic> ? j : null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> check() async {
    if (_showing) return;
    _lastCheck = DateTime.now();
    try {
      final json = await _fetch();
      if (json == null) return;
      final current = await currentCode();
      final info = UpdateInfo.fromJson(json, current);
      if (info.versionCode <= current || !info.apkUrl.startsWith('https://')) {
        _pending = null;
        return;
      }
      if (!info.forced &&
          (_dismissedSession || await _snoozed(info.versionCode))) {
        return;
      }
      _pending = info;
      _tryShow();
    } catch (e) {
      debugPrint('UPDATE: check failed: $e');
    }
  }

  /// Shows the pop-up only on the main screen, never during a call.
  void _tryShow() {
    final info = _pending;
    if (info == null || _showing) return;
    final nav = _nav?.currentState;
    final ctx = _nav?.currentContext;
    if (nav == null ||
        ctx == null ||
        nav.canPop() ||
        ActiveCall.current.value != null ||
        ActiveCall.running != null) {
      _retry ??=
          Timer.periodic(const Duration(seconds: 15), (_) => _tryShow());
      return;
    }
    _retry?.cancel();
    _retry = null;
    _showing = true;
    showUpdateDialog(ctx, info).then((_) async {
      _showing = false;
      if (!info.forced) {
        _pending = null;
        _dismissedSession = true;
        await snooze(info.versionCode);
      }
    });
  }

  Future<void> snooze(int code) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kSnoozeCode, code);
    await p.setInt(
      _kSnooze,
      DateTime.now().add(_snooze).millisecondsSinceEpoch,
    );
  }

  Future<bool> _snoozed(int code) async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kSnoozeCode) == code &&
        (p.getInt(_kSnooze) ?? 0) > DateTime.now().millisecondsSinceEpoch;
  }
}