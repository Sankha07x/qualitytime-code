import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IncomingCall {
  final String fromUid;
  final String sessionId;
  final bool video;
  const IncomingCall({
    required this.fromUid,
    required this.sessionId,
    required this.video,
  });
}

class GroupIncoming {
  final String fromUid;
  final String groupId;
  final String groupName;
  final String emoji;
  final int color;
  final String mode;
  final bool video;
  const GroupIncoming({
    required this.fromUid,
    required this.groupId,
    required this.groupName,
    required this.emoji,
    required this.color,
    required this.mode,
    required this.video,
  });
}

/// Listens on this user's personal channel for "ring" and "cancel" events,
/// and can ring another user by sending to their personal channel.
class IncomingCallService {
  final String myUid;
  final SupabaseClient _client = Supabase.instance.client;
  RealtimeChannel? _myChannel;
  Timer? _ringTimer;
  Timer? _restartTimer;
  static IncomingCallService? current;
  final _rawController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onRaw => _rawController.stream;
  bool _disposed = false;

  final _ringController = StreamController<IncomingCall>.broadcast();
  final _cancelController = StreamController<String>.broadcast();
  final _declineController = StreamController<String>.broadcast();
  final _ringingController = StreamController<String>.broadcast();
  final _busyController = StreamController<String>.broadcast();
  final _gringController = StreamController<GroupIncoming>.broadcast();
  Stream<GroupIncoming> get onGroupRing => _gringController.stream;

  Stream<String> get onBusy => _busyController.stream;
  Stream<IncomingCall> get onRing => _ringController.stream;
  Stream<String> get onCancel => _cancelController.stream;
  Stream<String> get onDecline => _declineController.stream;
  Stream<String> get onRinging => _ringingController.stream;

  IncomingCallService(this.myUid);

  Map<String, dynamic>? _data(Map<String, dynamic> payload) {
    final inner = payload['payload'] ?? payload;
    if (inner is Map && inner['d'] is Map) {
      return Map<String, dynamic>.from(inner['d'] as Map);
    }
    return null;
  }

  Future<void> start() async {
    final old = _myChannel;
    _myChannel = null;
    if (old != null) {
      try {
        await _client.removeChannel(old).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _myChannel = _client.channel('user:$myUid');
    current = this;
    for (final ev in const ['decline', 'ringing', 'busy']) {
      _myChannel!.onBroadcast(
        event: ev,
        callback: (p) {
          final d = _data(p);
          if (d == null || _rawController.isClosed) return;
          _rawController.add({
            'event': ev,
            'from': (d['from'] ?? '').toString(),
            'session': (d['session'] ?? '').toString(),
          });
        },
      );
    }
    _myChannel!
        .onBroadcast(
          event: 'ring',
          callback: (p) {
            final d = _data(p);
            if (d == null) return;
            debugPrint('RING received from ${d['from']}');
            _ringController.add(IncomingCall(
              fromUid: d['from'] as String,
              sessionId: d['session'] as String,
              video: d['video'] == true,
            ));
          },
        )
        .onBroadcast(
          event: 'cancel',
          callback: (p) {
            final d = _data(p);
            if (d == null) return;
            _cancelController.add(d['session'] as String);
          },
        )
        .onBroadcast(
          event: 'decline',
          callback: (p) {
            final d = _data(p);
            if (d == null) return;
            _declineController.add(d['session'] as String);
          },
        )
        .onBroadcast(
          event: 'ringing',
          callback: (p) {
            final d = _data(p);
            if (d == null) return;
            _ringingController.add(d['session'] as String);
          },
        )
        .onBroadcast(
          event: 'busy',
          callback: (p) {
            final d = _data(p);
            if (d == null) return;
            _busyController.add(d['session'] as String);
          },
        )
        .onBroadcast(
          event: 'gring',
          callback: (p) {
            final d = _data(p);
            if (d == null) return;
            _gringController.add(GroupIncoming(
              fromUid: (d['from'] ?? '').toString(),
              groupId: (d['group'] ?? '').toString(),
              groupName: (d['name'] ?? 'Group').toString(),
              emoji: (d['emoji'] ?? '👥').toString(),
              color: (d['color'] as num?)?.toInt() ?? 0xFF0D9488,
              mode: (d['mode'] ?? 'friends').toString(),
              video: d['video'] == true,
            ));
          },
        )
        .subscribe((status, error) {
      debugPrint('RING listener status: $status $error');
      if (!_disposed &&
          (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut)) {
        _restartTimer?.cancel();
        _restartTimer = Timer(const Duration(seconds: 5), () {
          if (!_disposed) start();
        });
      }
    });
  }

  static Future<void> _chain = Future.value();

  Future<void> _send(String toUid, String event, Map<String, dynamic> data) {
    final next = _chain.then((_) => _sendNow(toUid, event, data));
    _chain = next.catchError((_) {});
    return next;
  }

  Future<void> _sendNow(
      String toUid, String event, Map<String, dynamic> data) async {
    final ch = _client.channel('user:$toUid');
    try {
      final ready = Completer<void>();
      ch.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed && !ready.isCompleted) {
          ready.complete();
        }
      });
      await ready.future.timeout(const Duration(seconds: 10));
      await ch.sendBroadcastMessage(event: event, payload: {'d': data});
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('RING send failed: $e');
    } finally {
      try {
        await _client.removeChannel(ch).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
  }

  /// Rings the other phone every 3 seconds for up to 27 seconds.
  void startRinging({
    required String toUid,
    required String sessionId,
    required bool video,
  }) {
    _ringTimer?.cancel();
    bool inFlight = false;
    void ring() {
      if (inFlight) return;
      inFlight = true;
      _send(toUid, 'ring', {
        'from': myUid,
        'session': sessionId,
        'video': video,
      }).whenComplete(() => inFlight = false);
    }

    Future<void> ringRaw() => _send(toUid, 'ring', {
          'from': myUid,
          'session': sessionId,
          'video': video,
        });
    ring();
    var count = 0;
    _ringTimer = Timer.periodic(const Duration(seconds: 3), (t) {
      if (++count >= 9) {
        t.cancel();
        return;
      }
      ring();
    });
  }

  /// Callee: tells the caller the call was declined.
  Future<void> sendDecline({
    required String toUid,
    required String sessionId,
  }) =>
      _send(toUid, 'decline', {'session': sessionId});

  /// Callee: tells the caller this phone received the call and is ringing.
  Future<void> sendRinging({
    required String toUid,
    required String sessionId,
  }) =>
      _send(toUid, 'ringing', {'session': sessionId});

  /// Callee: tells the caller I'm already on another call.
  Future<void> sendBusy({
    required String toUid,
    required String sessionId,
  }) =>
      _send(toUid, 'busy', {'session': sessionId});

  /// Stops repeating the ring (call connected).
  void stopRingTimer() => _ringTimer?.cancel();

  /// Stops ringing and tells the other phone to close its incoming screen.
  Future<void> stopRinging({
    required String toUid,
    required String sessionId,
  }) async {
    _ringTimer?.cancel();
    await _send(toUid, 'cancel', {'session': sessionId});
  }

  void dispose() {
    _ringTimer?.cancel();
    _disposed = true;
    if (identical(current, this)) current = null;
    _rawController.close();
    _restartTimer?.cancel();
    final ch = _myChannel;
    _myChannel = null;
    if (ch != null) {
      _client.removeChannel(ch).then((_) {}, onError: (_) {});
    }
    _ringController.close();
    _cancelController.close();
    _declineController.close();
    _ringingController.close();
    _busyController.close();
    _gringController.close();
  }
}