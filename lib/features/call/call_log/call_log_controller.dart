import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CallResult { answered, missed, declined, cancelled }

/// One line in the call history.
class CallLogEntry {
  final String uid;
  final bool outgoing;
  final bool video;
  final CallResult result;
  final DateTime time;
  final int seconds;

  const CallLogEntry({
    required this.uid,
    required this.outgoing,
    required this.video,
    required this.result,
    required this.time,
    this.seconds = 0,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'outgoing': outgoing,
        'video': video,
        'result': result.name,
        'time': time.toIso8601String(),
        'seconds': seconds,
      };

  factory CallLogEntry.fromJson(Map<String, dynamic> j) => CallLogEntry(
        uid: j['uid'] as String,
        outgoing: j['outgoing'] == true,
        video: j['video'] == true,
        result: CallResult.values.firstWhere(
          (r) => r.name == j['result'],
          orElse: () => CallResult.cancelled,
        ),
        time: DateTime.parse(j['time'] as String),
        seconds: (j['seconds'] as num?)?.toInt() ?? 0,
      );
}

/// Keeps the last 100 calls on the phone, newest first.
class CallLogController {
  static const _key = 'call_log_v1';
  static const _maxEntries = 100;
  bool _disposed = false;

  final entries = ValueNotifier<List<CallLogEntry>>([]);

  CallLogController() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || _disposed) return;
      final saved = (jsonDecode(raw) as List)
          .map((e) => CallLogEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // anything logged before loading finished is newer, so it goes first
      entries.value = [...entries.value, ...saved];
    } catch (e) {
      debugPrint('Call log load failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(entries.value.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Call log save failed: $e');
    }
  }

  Future<void> add(CallLogEntry entry) async {
    if (_disposed) return;
    final list = [entry, ...entries.value];
    if (list.length > _maxEntries) list.removeRange(_maxEntries, list.length);
    entries.value = list;
    await _save();
  }

  Future<void> clear() async {
    if (_disposed) return;
    entries.value = [];
    await _save();
  }

  void dispose() {
    _disposed = true;
    entries.dispose();
  }
}
