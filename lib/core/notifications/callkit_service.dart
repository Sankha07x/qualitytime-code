import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class AcceptedCall {
  final String sessionId;
  final String callerUid;
  final bool video;
  AcceptedCall(this.sessionId, this.callerUid, this.video);
}

class DeclinedCall {
  final String sessionId;
  final String callerUid;
  DeclinedCall(this.sessionId, this.callerUid);
}

/// Shows the native full-screen ringing UI and reports when the user
/// taps Accept. Safe to call from the background push isolate.
class CallKitService {
  CallKitService._();
  static final CallKitService instance = CallKitService._();

  final _acceptedCtrl = StreamController<AcceptedCall>.broadcast();
  Stream<AcceptedCall> get onAccepted => _acceptedCtrl.stream;
  final _declinedCtrl = StreamController<DeclinedCall>.broadcast();
  Stream<DeclinedCall> get onDeclined => _declinedCtrl.stream;
  bool _started = false;

  /// Shows the incoming-call screen from push data.
  static Future<void> showIncoming(Map<String, dynamic> data) async {
    try {
      final sessionId = data['session_id']?.toString() ?? '';
      if (sessionId.isEmpty) return;
      final callerUid = data['caller_uid']?.toString() ?? '';
      final name = data['caller_name']?.toString() ?? callerUid;
      final video = data['call_type']?.toString() == 'video';
      final photo = data['caller_photo']?.toString() ?? '';

      final params = CallKitParams(
        id: sessionId,
        nameCaller: name,
        appName: 'QualityTime',
        avatar: photo,
        handle: video ? 'Video call' : 'Voice call',
        type: video ? 1 : 0,
        duration: 30000,
        extra: <String, dynamic>{
          'session_id': sessionId,
          'caller_uid': callerUid,
          'video': video,
        },
        android: AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0F766E',
          backgroundUrl: photo,
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Incoming Call',
          missedCallNotificationChannelName: 'Missed Call',
        ),
      );
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      debugPrint('CALLKIT: show failed: $e');
    }
  }

  /// Starts listening for the Accept button. Call once.
  void start() {
    if (_started) return;
    _started = true;
    FlutterCallkitIncoming.onEvent.listen((dynamic event) {
      try {
        if (event == null) return;
        final name =
            event.event.toString().toLowerCase().replaceAll('_', '');
        if (name.contains('calldecline')) {
          final d = _fromMap(event.body);
          if (d != null) {
            _declinedCtrl.add(DeclinedCall(d.sessionId, d.callerUid));
          }
          return;
        }
        if (!name.contains('callaccept')) return;
        final accepted = _fromMap(event.body);
        if (accepted != null) _acceptedCtrl.add(accepted);
      } catch (e) {
        debugPrint('CALLKIT: event error: $e');
      }
    });
  }

  /// If the app was launched by tapping Accept (app was closed), the
  /// event fires before the UI exists — pick it up from active calls.
  Future<void> emitAcceptedFromActiveCalls() async {
    try {
      final dynamic calls = await FlutterCallkitIncoming.activeCalls();
      if (calls is List) {
        for (final dynamic c in calls) {
          if (_isAccepted(c)) {
            final accepted = _fromMap(_toMap(c));
            if (accepted != null) _acceptedCtrl.add(accepted);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('CALLKIT: activeCalls failed: $e');
    }
  }

  bool _isAccepted(dynamic c) {
    try {
      if (c.isAccepted == true) return true;
    } catch (_) {}
    try {
      final m = c.toJson();
      if (m is Map && m['isAccepted'] == true) return true;
    } catch (_) {}
    try {
      if (c is Map && c['isAccepted'] == true) return true;
    } catch (_) {}
    return false;
  }

  dynamic _toMap(dynamic c) {
    if (c is Map) return c;
    try {
      return c.toJson();
    } catch (_) {
      return null;
    }
  }

  AcceptedCall? _fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final extraRaw = map['extra'];
    final extra =
        extraRaw is Map ? Map<String, dynamic>.from(extraRaw) : <String, dynamic>{};
    final sessionId = (extra['session_id'] ?? map['id'] ?? '').toString();
    if (sessionId.isEmpty) return null;
    final callerUid = (extra['caller_uid'] ?? '').toString();
    final video = extra['video'] == true || extra['video'] == 'true';
    return AcceptedCall(sessionId, callerUid, video);
  }

  Future<void> endCall(String id) async {
    try {
      await FlutterCallkitIncoming.endCall(id);
    } catch (e) {
      debugPrint('CALLKIT: endCall failed: $e');
    }
  }

  Future<void> requestPermissions() async {
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Notification permission',
        'rationaleMessagePermission':
            'Notification permission is required to show incoming calls.',
        'postNotificationMessageRequired':
            'Please allow notifications from Settings to receive calls.',
      });
    } catch (e) {
      debugPrint('CALLKIT: permission request failed: $e');
    }
  }
}