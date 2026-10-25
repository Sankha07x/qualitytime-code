import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signaling_interface.dart';

/// Supabase Realtime Channel implementation of [SignalingInterface].
/// Broadcast only, nothing is stored in a table.
class SupabaseSignaling implements SignalingInterface {
  final SupabaseClient _client = Supabase.instance.client;
  RealtimeChannel? _channel;
  String _sessionId = '';
  bool _leaving = false;
  Timer? _reconnect;

  final _sdpController = StreamController<Map<String, dynamic>>.broadcast();
  final _iceController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController = StreamController<bool>.broadcast();

  Map<String, dynamic> _unwrap(Map<String, dynamic> payload) {
    final inner = payload['payload'] ?? payload;
    if (inner is Map && inner['d'] is Map) {
      final d = Map<String, dynamic>.from(inner['d'] as Map);
      debugPrint('SIGNAL recv: ${d['type'] ?? 'ice'}');
      return d;
    }
    debugPrint('SIGNAL recv (unrecognized): $payload');
    return {};
  }

  Future<void> _open() async {
    final old = _channel;
    _channel = null;
    if (old != null) {
      try {
        await _client.removeChannel(old);
      } catch (_) {}
    }
    final ch = _client.channel('call:$_sessionId');
    _channel = ch;
    ch
        .onBroadcast(
          event: 'sdp',
          callback: (payload) {
            if (!_sdpController.isClosed) _sdpController.add(_unwrap(payload));
          },
        )
        .onBroadcast(
          event: 'ice',
          callback: (payload) {
            if (!_iceController.isClosed) _iceController.add(_unwrap(payload));
          },
        )
        .onPresenceSync((_) {
          if (!_presenceController.isClosed) _presenceController.add(true);
        })
        .onPresenceLeave((_) {
          if (!_presenceController.isClosed) _presenceController.add(false);
        });

    final ready = Completer<void>();
    ch.subscribe((status, error) {
      debugPrint('SIGNAL status: $status $error');
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (!ready.isCompleted) ready.complete();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        if (ready.isCompleted && !_leaving && identical(ch, _channel)) {
          _scheduleReconnect();
        }
      }
    });
    await ready.future.timeout(const Duration(seconds: 10));
  }

  void _scheduleReconnect() {
    if (_leaving) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 2), () async {
      if (_leaving) return;
      try {
        debugPrint('SIGNAL reconnecting');
        await _open();
      } catch (e) {
        debugPrint('SIGNAL reconnect failed: $e');
        _scheduleReconnect();
      }
    });
  }

  @override
  Future<void> joinSession(String sessionId) async {
    debugPrint('SIGNAL join: call:$sessionId');
    _sessionId = sessionId;
    _leaving = false;
    await _open();
  }

  @override
  Future<void> leaveSession() async {
    _leaving = true;
    _reconnect?.cancel();
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await _client.removeChannel(ch);
      } catch (e) {
        debugPrint('SIGNAL leave failed: $e');
      }
    }
  }

  Future<void> _send(String event, Map<String, dynamic> data) async {
    for (var i = 0; i < 2; i++) {
      final ch = _channel;
      if (ch == null) return;
      try {
        await ch.sendBroadcastMessage(event: event, payload: {'d': data});
        return;
      } catch (e) {
        debugPrint('SIGNAL send failed ($event): $e');
        if (i == 0) await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  @override
  Future<void> sendSessionDescription(Map<String, dynamic> description) async {
    debugPrint('SIGNAL send: ${description['type']}');
    await _send('sdp', description);
  }

  @override
  Future<void> sendIceCandidate(Map<String, dynamic> candidate) async {
    await _send('ice', candidate);
  }

  @override
  Stream<Map<String, dynamic>> get onSessionDescription => _sdpController.stream;

  @override
  Stream<Map<String, dynamic>> get onIceCandidate => _iceController.stream;

  @override
  Stream<bool> get onPeerPresenceChanged => _presenceController.stream;

  void dispose() {
    _leaving = true;
    _reconnect?.cancel();
    _sdpController.close();
    _iceController.close();
    _presenceController.close();
  }
}