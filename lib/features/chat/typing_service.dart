import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live "typing" and "online in this chat" signals.
/// Nothing is stored. Uses Supabase Realtime broadcast only.
class TypingService {
  final String myUid;
  final String peerUid;
  final typing = ValueNotifier<bool>(false);
  final online = ValueNotifier<bool>(false);

  RealtimeChannel? _ch;
  Timer? _beat;
  Timer? _typingOff;
  Timer? _onlineOff;
  Timer? _sendOff;
  bool _ready = false;
  bool _disposed = false;
  bool _sentOn = false;
  DateTime _lastOn = DateTime.fromMillisecondsSinceEpoch(0);

  TypingService({required this.myUid, required this.peerUid});

  String get _name {
    final a = [myUid, peerUid]..sort();
    return 'typing_${a[0]}_${a[1]}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  void start() {
    try {
      _ch = Supabase.instance.client
          .channel(_name)
          .onBroadcast(event: 'typing', callback: _onTyping)
          .onBroadcast(event: 'here', callback: _onHere)
          .onBroadcast(event: 'bye', callback: (_) => _peerGone())
          .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed && !_disposed) {
          _ready = true;
          _send('here', {'u': myUid, 'r': 1});
          _beat = Timer.periodic(const Duration(seconds: 6),
              (_) => _send('here', {'u': myUid, 'r': 0}));
        }
      });
    } catch (e) {
      debugPrint('TYPING start failed: $e');
    }
  }

  Map<String, dynamic> _data(Map<String, dynamic> p) {
    final d = p['payload'];
    return d is Map ? Map<String, dynamic>.from(d) : p;
  }

  void _onTyping(Map<String, dynamic> p) {
    if (_disposed) return;
    final d = _data(p);
    if (d['u'] != peerUid) return;
    final on = d['on'] == true;
    typing.value = on;
    _typingOff?.cancel();
    if (on) {
      _typingOff = Timer(const Duration(seconds: 6), () {
        if (!_disposed) typing.value = false;
      });
    }
    _markOnline();
  }

  void _onHere(Map<String, dynamic> p) {
    if (_disposed) return;
    final d = _data(p);
    if (d['u'] != peerUid) return;
    _markOnline();
    if (d['r'] == 1) _send('here', {'u': myUid, 'r': 0});
  }

  void _markOnline() {
    online.value = true;
    _onlineOff?.cancel();
    _onlineOff = Timer(const Duration(seconds: 14), _peerGone);
  }

  void _peerGone() {
    if (_disposed) return;
    online.value = false;
    typing.value = false;
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

  /// Call with true on every key press, false when the box is empty.
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
    _send('bye', {'u': myUid});
    _disposed = true;
    _beat?.cancel();
    _typingOff?.cancel();
    _onlineOff?.cancel();
    _sendOff?.cancel();
    final ch = _ch;
    Future.delayed(const Duration(milliseconds: 400), () {
      try {
        ch?.unsubscribe();
      } catch (_) {}
    });
    typing.dispose();
    online.dispose();
  }
}