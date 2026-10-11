import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';
import '../signaling/incoming_call_service.dart';
import 'dart:io';
import 'dart:ui' show Color, DartPluginRegistrant;

/// Incoming-call notification (Answer / Decline) and the ongoing-call
/// foreground-service notification (timer, End call).

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse r) {
  if (r.actionId == 'decline') CallNotification.declineInBackground(r.payload);
}

class CallNotification {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _launchChecked = false;
  static const _id = 4242;
  static const _ongoingId = 4343;
  static const _kRing = 'ring_notif_at';

  /// 'answer' or 'decline' tapped on the incoming notification.
  static String? pendingAction;
  static int _actionAt = 0;

  /// Set by the contacts screen to react when the app is already running.
  static void Function(String action)? actionListener;

  /// Caller details from the notification the user tapped Answer on.
  static Map<String, dynamic>? pendingCall;

  static Map<String, dynamic>? _parse(String? p) {
    try {
      final m = jsonDecode(p ?? '');
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? takeCall() {
    final c = pendingCall;
    pendingCall = null;
    if (c == null) return null;
    final fresh = DateTime.now().millisecondsSinceEpoch - _actionAt < 40000;
    return fresh ? c : null;
  }

  /// Decline tapped on the notification: no app, no screen.
  static Future<void> declineInBackground(String? payload) async {
    try {
      DartPluginRegistrant.ensureInitialized();
      final m = _parse(payload);
      final uid = m?['u']?.toString() ?? '';
      final session = m?['s']?.toString() ?? '';
      if (uid.isEmpty || session.isEmpty) return;
      await _declineHttp(uid, session);
      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
        );
      } catch (_) {}
      final svc = IncomingCallService('');
      await svc.sendDecline(toUid: uid, sessionId: session);
      svc.dispose();
      try {
        await _plugin.cancel(_id);
      } catch (_) {}
    } catch (e) {
      debugPrint('DECLINE: $e');
    }
  }

  /// Sends "decline" over plain HTTP (no websocket needed in background).
  static Future<void> _declineHttp(String uid, String session) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final r = await c.postUrl(
          Uri.parse('${AppConfig.supabaseUrl}/realtime/v1/api/broadcast'));
      r.headers.set('apikey', AppConfig.supabaseAnonKey);
      r.headers.set('Authorization', 'Bearer ${AppConfig.supabaseAnonKey}');
      r.headers.contentType = ContentType.json;
      r.write(jsonEncode({
        'messages': [
          {
            'topic': 'user:$uid',
            'event': 'decline',
            'payload': {
              'd': {'session': session}
            },
          }
        ]
      }));
      final resp = await r.close().timeout(const Duration(seconds: 8));
      await resp.drain();
    } catch (e) {
      debugPrint('DECLINE http: $e');
    } finally {
      c.close(force: true);
    }
  }

  static Future<ByteArrayAndroidBitmap?> _photo(String? url) async {
    if (url == null || !url.startsWith('http')) return null;
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final r = await (await c.getUrl(Uri.parse(url)))
          .close()
          .timeout(const Duration(seconds: 2));
      if (r.statusCode != 200) return null;
      final b = await r.fold<List<int>>(<int>[], (a, d) => a..addAll(d));
      return ByteArrayAndroidBitmap(Uint8List.fromList(b));
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  /// Set in main.dart: tap on / End button of the ongoing-call notification.
  static void Function()? openCallListener;
  static void Function()? endCallListener;

  static void _onResponse(NotificationResponse r) {
    final a = r.actionId;
    if (a == 'end') {
      endCallListener?.call();
      return;
    }
    if (r.payload == 'ongoing' && (a == null || a.isEmpty)) {
      openCallListener?.call();
      return;
    }
    if (a != 'answer' && a != 'decline') return;
    pendingAction = a;
    _actionAt = DateTime.now().millisecondsSinceEpoch;
    if (a == 'answer') pendingCall = _parse(r.payload);
    actionListener?.call(a!);
  }

  static Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    _ready = true;
  }

  /// App was cold-started by tapping Answer / Decline.
  static Future<void> checkLaunchAction() async {
    if (_launchChecked) return;
    _launchChecked = true;
    await _init();
    final d = await _plugin.getNotificationAppLaunchDetails();
    final r = d?.notificationResponse;
    if (d?.didNotificationLaunchApp == true && r != null) _onResponse(r);
  }

  

  /// Returns the tapped action once (only if it is fresh).
  static String? takeAction() {
    final a = pendingAction;
    pendingAction = null;
    if (a == null) return null;
    final fresh = DateTime.now().millisecondsSinceEpoch - _actionAt < 40000;
    return fresh ? a : null;
  }

  static Future<void> _mark(int t) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kRing, t);
    } catch (_) {}
  }

  /// True if a call notification was shown in the last 35 seconds.
  static Future<bool> recentlyRang() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final t = p.getInt(_kRing) ?? 0;
      return DateTime.now().millisecondsSinceEpoch - t < 35000;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermissions() async {
    await _init();
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await a?.requestNotificationsPermission();
    await a?.requestFullScreenIntentPermission();
  }

  static Future<void> show(Map<String, dynamic> data) async {
    await _init();
    final session = data['session_id']?.toString() ?? '';
    if (session.isEmpty) return;
    final name = data['caller_name']?.toString() ?? 'Someone';
    final video = data['call_type']?.toString() == 'video';
    await _mark(DateTime.now().millisecondsSinceEpoch);
    var tone = 'system';
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      tone = p.getString('set_incoming_tone') ?? 'system';
    } catch (_) {}
    const builtIn = {
      'classic', 'chime', 'marimba', 'digital', 'pulse', 'bell', 'soft',
    };
    final useRaw = builtIn.contains(tone);
    var accent = 0xFF009688;
    try {
      final p = await SharedPreferences.getInstance();
      accent = p.getInt('set_accent') ?? accent;
    } catch (_) {}
    final bigIcon = await _photo(data['caller_photo']?.toString());
    await _plugin.show(
      _id,
      name,
      video ? 'Incoming video call' : 'Incoming voice call',
      NotificationDetails(
        android: AndroidNotificationDetails(
          useRaw ? 'incoming_calls_v3_$tone' : 'incoming_calls_v2',
          'Incoming calls',
          channelDescription: 'Rings when someone calls you',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          color: Color(accent),
          colorized: true,
          subText: 'QualityTime',
          largeIcon: bigIcon,
          fullScreenIntent: true,
          ongoing: true,
          timeoutAfter: 30000,
          visibility: NotificationVisibility.public,
          playSound: true,
          sound: useRaw
              ? RawResourceAndroidNotificationSound('tone_$tone')
              : const UriAndroidNotificationSound(
                  'content://settings/system/ringtone'),
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          additionalFlags: Int32List.fromList([4]),
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 800, 600, 800, 600, 800]),
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction('decline', 'Decline',
                showsUserInterface: false),
            AndroidNotificationAction('answer', 'Answer',
                showsUserInterface: true),
          ],
        ),
      ),
      payload: jsonEncode({
        's': session,
        'u': data['caller_uid']?.toString() ?? '',
        'n': name,
        'v': video,
        'p': data['caller_photo']?.toString() ?? '',
      }),
    );
  }

  static Future<void> cancel() async {
    await _init();
    await _mark(0);
    await _plugin.cancel(_id);
  }

  /// Starts the foreground service + ongoing-call notification.
  /// Safe to call again (e.g. when the camera is added to a voice call).
  static Future<void> startOngoing({
    required String name,
    required bool video,
    required DateTime since,
  }) async {
    try {
      await _init();
      final a = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await a?.startForegroundService(
        _ongoingId,
        name,
        video ? 'Ongoing video call' : 'Ongoing voice call',
        notificationDetails: AndroidNotificationDetails(
          'ongoing_call_v2',
          'Ongoing call',
          channelDescription: 'Shown while a call is active',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
          enableVibration: false,
          category: AndroidNotificationCategory.call,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          when: since.millisecondsSinceEpoch,
          usesChronometer: true,
          visibility: NotificationVisibility.public,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              'end',
              'End call',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
        payload: 'ongoing',
        startType: AndroidServiceStartType.startSticky,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeMicrophone,
          if (video) AndroidServiceForegroundType.foregroundServiceTypeCamera,
        },
      );
    } catch (e) {
      debugPrint('ONGOING: $e');
    }
  }

  static Future<void> stopOngoing() async {
    try {
      await _init();
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      final a = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await a?.stopForegroundService();
    } catch (_) {}
  }
}