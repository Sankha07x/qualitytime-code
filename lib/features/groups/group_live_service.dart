import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live "who is typing" for one group, plus a small "read" nudge so
/// senders refresh their ticks at once. Nothing is stored.
class GroupLiveService {
  final String groupId;
  final String myUid;
  final typing = ValueNotifier<List<String>>([]);

  /// Set by the screen: someone read messages, so refresh the ticks.
  VoidCallback? onNudge;

  RealtimeChannel? _ch;
  final _until = <String, DateTime>{};
  Timer? _sweep;
  Timer? _sendOff;
  bool _ready = false;
  bool _disposed = false;
  bool _sentOn = false;
  DateTime _lastOn = DateTime.fromMillisecondsSinceEpoch(0);

  GroupLiveService({required this.groupId, required this.myUid});

  void start() {
    try {
      _ch = Supabase.instance.client
          .channel('gtyping_$groupId')
          .onBroadcast(event: 'typing', callback: _onTyping)
          .onBroadcast(event: 'read', callback: _onRead)
          .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed && !_disposed) {
          _ready = true;
        }
      });
      _sweep = Timer.periodic(const Duration(seconds: 2), (_) => _clean());
    } catch (e) {
      debugPrint('GTYPING start failed: $e');
    }
  }

  Map<String, dynamic> _data(Map<String, dynamic> p) {
    final d = p['payload'];
    return d is Map ? Map<String, dynamic>.from(d) : p;
  }

  void _publish() {
    if (_disposed) return;
    final l = _until.keys.toList();
    if (!listEquals(l, typing.value)) typing.value = l;
  }

  void _clean() {
    if (_disposed || _until.isEmpty) return;
    final now = DateTime.now();
    _until.removeWhere((_, t) => t.isBefore(now));
    _publish();
  }

  void _onTyping(Map<String, dynamic> p) {
    if (_disposed) return;
    final d = _data(p);
    final u = d['u']?.toString();
    if (u == null || u == myUid) return;
    if (d['on'] == true) {
      _until[u] = DateTime.now().add(const Duration(seconds: 6));
    } else {
      _until.remove(u);
    }
    _publish();
  }

  void _onRead(Map<String, dynamic> p) {
    if (_disposed) return;
    final u = _data(p)['u']?.toString();
    if (u == null || u == myUid) return;
    onNudge?.call();
  }

  void _send(String event, Map<String, dynamic> payload) {
    final ch = _ch;
    if (ch == null || !_ready || _disposed) return;
    _post(ch, event, payload);
  }

  Future<void> _post(
      RealtimeChannel ch, String event, Map<String, dynamic> payload) async {
    try {
      await ch.sendBroadcastMessage(event: event, payload: payload);
    } catch (_) {}
  }

  /// Tell the others I just read messages.
  void nudge() => _send('read', {'u': myUid});

  /// Call with true while typing, false when the box is empty.
  void setTyping(bool on) {
    if (_disposed) return;
    _sendOff?.cancel();
    if (on) {
      final now = DateTime.now();
      if (!_sentOn || now.difference(_lastOn).inSeconds >= 3) {
        _sentOn = true;
        _lastOn = now;
        _send('typing', {'u': myUid, 'on': true});
      }
      _sendOff = Timer(const Duration(seconds: 4), () => setTyping(false));
    } else if (_sentOn) {
      _sentOn = false;
      _send('typing', {'u': myUid, 'on': false});
    }
  }

  void dispose() {
    if (_disposed) return;
    if (_sentOn) _send('typing', {'u': myUid, 'on': false});
    _disposed = true;
    _sweep?.cancel();
    _sendOff?.cancel();
    final ch = _ch;
    Future.delayed(const Duration(milliseconds: 400), () {
      try {
        ch?.unsubscribe();
      } catch (_) {}
    });
    typing.dispose();
  }
}