import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signaling_interface.dart';

/// Supabase Realtime Channel implementation of [SignalingInterface].
/// Broadcast only, nothing is stored in a table.
class SupabaseSignaling implements SignalingInterface {
  final SupabaseClient _client = Supabase.instance.client;
  RealtimeChannel? _channel;

  final _sdpController = StreamController<Map<String, dynamic>>.broadcast();
  final _iceController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController = StreamController<bool>.broadcast();

  /// Our data is sent under the key 'd' so it can't clash with Supabase's
  /// own 'type' field. Returns {} if the message isn't in that shape.
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

  @override
  Future<void> joinSession(String sessionId) async {
    debugPrint('SIGNAL join: call:$sessionId');
    _channel = _client.channel('call:$sessionId');

    _channel!
        .onBroadcast(
          event: 'sdp',
          callback: (payload) => _sdpController.add(_unwrap(payload)),
        )
        .onBroadcast(
          event: 'ice',
          callback: (payload) => _iceController.add(_unwrap(payload)),
        )
        .onPresenceSync((_) => _presenceController.add(true))
        .onPresenceLeave((_) => _presenceController.add(false));

    final ready = Completer<void>();
    _channel!.subscribe((status, error) {
      debugPrint('SIGNAL status: $status $error');
      if (status == RealtimeSubscribeStatus.subscribed && !ready.isCompleted) {
        ready.complete();
      }
    });
    await ready.future.timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> leaveSession() async {
    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }
  }

  @override
  Future<void> sendSessionDescription(Map<String, dynamic> description) async {
    debugPrint('SIGNAL send: ${description['type']}');
    await _channel?.sendBroadcastMessage(
      event: 'sdp',
      payload: {'d': description},
    );
  }

  @override
  Future<void> sendIceCandidate(Map<String, dynamic> candidate) async {
    await _channel?.sendBroadcastMessage(
      event: 'ice',
      payload: {'d': candidate},
    );
  }

  @override
  Stream<Map<String, dynamic>> get onSessionDescription => _sdpController.stream;

  @override
  Stream<Map<String, dynamic>> get onIceCandidate => _iceController.stream;

  @override
  Stream<bool> get onPeerPresenceChanged => _presenceController.stream;

  void dispose() {
    _sdpController.close();
    _iceController.close();
    _presenceController.close();
  }
}