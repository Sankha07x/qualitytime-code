import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../firebase_options.dart';
import 'callkit_service.dart';
import 'call_notification.dart';
import '../../config/app_config.dart';
import '../signaling/incoming_call_service.dart';

/// Runs when a push arrives while the app is closed or in the background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);
  if (message.data['type'] == 'incoming_call') {
    await CallNotification.show(message.data);
    await _sendRingingAck(message.data);
  }
}

/// Tells the caller this phone got the call (works with the app closed).
Future<void> _sendRingingAck(Map<String, dynamic> data) async {
  try {
    final caller = data['caller_uid']?.toString() ?? '';
    final session = data['session_id']?.toString() ?? '';
    if (caller.isEmpty || session.isEmpty) return;
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
    } catch (_) {}
    final svc = IncomingCallService('');
    await svc.sendRinging(toUid: caller, sessionId: session);
    svc.dispose();
  } catch (e) {
    debugPrint('RINGING ack failed: $e');
  }
}

/// Saves this phone's FCM token to Supabase so the server can push
/// incoming-call alerts to it. Never throws.
class PushNotificationService {
  final _fcm = FirebaseMessaging.instance;
  final _db = Supabase.instance.client;

  Future<void> init() async {
    try {
      await _fcm.requestPermission();
      await CallNotification.requestPermissions();
      final token = await _fcm.getToken();
      if (token != null) await _save(token);
      _fcm.onTokenRefresh.listen(_save);
    } catch (e) {
      debugPrint('PUSH: init failed: $e');
    }
  }

  Future<void> _save(String token) async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      await _db.from('profiles').update({'fcm_token': token}).eq('id', uid);
      debugPrint('PUSH: token saved');
    } catch (e) {
      debugPrint('PUSH: save failed: $e');
    }
  }
}