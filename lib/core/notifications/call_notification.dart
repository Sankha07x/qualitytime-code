import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';
import '../signaling/incoming_call_service.dart';
import '../security/e2ee_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'dart:ui' show Color, DartPluginRegistrant;

/// Incoming-call notification (Answer / Decline) and the ongoing-call
/// foreground-service notification (timer, End call).

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse r) {
  if (r.actionId == 'decline') CallNotification.declineInBackground(r.payload);
  if (r.actionId == 'reply' || r.actionId == 'markread') {
    CallNotification.quickAction(r);
  }
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

  /// Chat / friend request / missed call notification that was tapped.
  static Map<String, dynamic>? pendingOpen;
  static void Function(Map<String, dynamic> p)? openListener;

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
      await _mark(0);
      try {
        await _plugin.cancel(_id);
      } catch (_) {}
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

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Adds messages to the chat history saved on this phone.
  static Future<void> _appendLocal(
      String peer, List<Map<String, dynamic>> add) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/chat_${_safeName(peer)}.json');
    var list = <dynamic>[];
    if (await f.exists()) {
      list = jsonDecode(await f.readAsString()) as List;
    }
    final have = {for (final j in list) j['id'].toString()};
    for (final a in add) {
      if (!have.contains(a['id'].toString())) list.add(a);
    }
    list.sort((a, b) => DateTime.parse(a['at'].toString())
        .compareTo(DateTime.parse(b['at'].toString())));
    await f.writeAsString(jsonEncode(list), flush: true);
  }

  /// Saves waiting text messages from [peer] on this phone, then marks them
  /// read in the cloud (same steps the chat screen does when it opens).
  static Future<void> _saveIncomingText(
      SupabaseClient db, String me, String peer) async {
    final rows = await db
        .from('chat_messages')
        .select('id, body, created_at, reply_to, reply_text, reply_from')
        .eq('from_uid', peer)
        .eq('to_uid', me)
        .eq('kind', 'text')
        .isFilter('read_at', null)
        .order('created_at');
    final list = <Map<String, dynamic>>[];
    for (final r in rows as List) {
      final rawB = r['body']?.toString();
      if (rawB != null &&
          E2eeService.isEncryptedText(rawB) &&
          await E2eeService.decryptPeerText(peer, rawB) ==
              '🔒 Encrypted message') {
        E2eeService.forgetPeer(peer);
        continue;
      }
      final rawRx = r['reply_text']?.toString();
      list.add({
        'id': r['id'],
        'from': peer,
        'to': me,
        'kind': 'text',
        'body': rawB == null
            ? null
            : await E2eeService.decryptPeerText(peer, rawB),
        'fileName': null,
        'localName': null,
        'fileSize': null,
        'at': DateTime.parse(r['created_at'].toString())
            .toUtc()
            .toIso8601String(),
        'status': 2,
        'rt': r['reply_to'],
        'rx': rawRx == null
            ? null
            : await E2eeService.decryptPeerText(peer, rawRx),
        'rf': r['reply_from'],
      });
    }
    if (list.isEmpty) return;
    await _appendLocal(peer, list);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final x in list) {
      try {
        await db.from('chat_messages').update({
          'read_at': now,
          'delivered_at': now,
          'body': null,
          'file_path': null,
          'file_name': null,
          'reply_text': null,
        }).eq('id', x['id'] as String);
      } catch (_) {}
    }
  }

  /// Reply / Mark as read tapped on a chat or group-chat notification.
  /// Works with the app closed.
  static Future<void> quickAction(NotificationResponse r) async {
    final isReply = r.actionId == 'reply';
    try {
      DartPluginRegistrant.ensureInitialized();
      final m = _parse(r.payload);
      if (m == null) return;
      var text = (r.input ?? '').trim();
      if (isReply && text.isEmpty) return;
      if (text.length > 4000) text = text.substring(0, 4000);
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final key = '${r.id}|${r.actionId}|$text';
      final now = DateTime.now().millisecondsSinceEpoch;
      if (p.getString('quick_last') == key &&
          now - (p.getInt('quick_last_at') ?? 0) < 8000) {
        return; // the same tap arrived twice
      }
      await p.setString('quick_last', key);
      await p.setInt('quick_last_at', now);
      await _init();
      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
        );
      } catch (_) {}
      final db = Supabase.instance.client;
      for (var i = 0; i < 6 && db.auth.currentUser == null; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      final authId = db.auth.currentUser?.id;
      if (authId == null) throw 'not signed in';
      final prof =
          await db.from('profiles').select('uid').eq('id', authId).single();
      final me = prof['uid'].toString();
      final kind = m['k']?.toString() ?? '';
      if (kind == 'chat') {
        final peer = m['u']?.toString() ?? '';
        if (peer.isEmpty) return;
        await _saveIncomingText(db, me, peer);
        if (isReply) {
          final enc = await E2eeService.encryptPeerText(peer, text);
          if (!E2eeService.isEncryptedText(enc)) throw 'key not ready';
          final row = await db
              .from('chat_messages')
              .insert({
                'from_uid': me,
                'to_uid': peer,
                'kind': 'text',
                'body': enc,
              })
              .select('id, created_at')
              .single();
          await _appendLocal(peer, [
            {
              'id': row['id'],
              'from': me,
              'to': peer,
              'kind': 'text',
              'body': text,
              'fileName': null,
              'localName': null,
              'fileSize': null,
              'at': DateTime.parse(row['created_at'].toString())
                  .toUtc()
                  .toIso8601String(),
              'status': 0,
            }
          ]);
        }
      } else if (kind == 'group_chat') {
        final gid = m['g']?.toString() ?? '';
        if (gid.isEmpty) return;
        if (isReply) {
          final enc = await E2eeService.encryptGroupText(gid, me, text);
          if (!E2eeService.isEncryptedText(enc)) throw 'key not ready';
          await db.from('group_messages').insert({
            'group_id': gid,
            'from_uid': me,
            'body': enc,
          });
        }
        await p.setInt('gread_$gid', DateTime.now().millisecondsSinceEpoch);
      }
      if (isReply && r.id != null) {
        final origText = m['t']?.toString() ?? '';
        final senderName = m['n']?.toString() ?? 'QualityTime';
        final updatedBody = origText.isNotEmpty
            ? '$origText\nYou: $text'
            : 'You: $text';
        var accent = 0xFF009688;
        try {
          accent = p.getInt('set_accent') ?? accent;
        } catch (_) {}
        await _plugin.show(
          r.id!,
          senderName,
          updatedBody,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'messages_v1',
              'Messages and alerts',
              channelDescription:
                  'New chats, missed calls and friend requests',
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.message,
              color: Color(accent),
              styleInformation: BigTextStyleInformation(updatedBody),
              showWhen: true,
              actions: const <AndroidNotificationAction>[
                AndroidNotificationAction(
                  'reply',
                  'Reply',
                  showsUserInterface: false,
                  cancelNotification: false,
                  inputs: <AndroidNotificationActionInput>[
                    AndroidNotificationActionInput(
                        label: 'Type a message'),
                  ],
                ),
                AndroidNotificationAction(
                  'call_now',
                  'Call now',
                  showsUserInterface: true,
                ),
              ],
            ),
          ),
          payload: jsonEncode({
            ...m,
            't': origText,
            'last_reply': text,
          }),
        );
      } else if (r.id != null) {
        await _plugin.cancel(r.id!);
      }
    } catch (e) {
      debugPrint('QUICK: $e');
      if (isReply && r.id != null) {
        try {
          await _init();
          await _plugin.show(
            r.id!,
            'Reply not sent',
            'Open QualityTime and try again.\nYour message: ${r.input ?? ''}',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'messages_v1',
                'Messages and alerts',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
            payload: r.payload,
          );
        } catch (_) {}
      }
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
    if (a == 'reply' || a == 'markread') {
      quickAction(r);
      return;
    }
    if (a == 'end') {
      endCallListener?.call();
      return;
    }
    if (a == 'call' || a == 'call_now') {
      final pm = _parse(r.payload);
      if (pm != null) {
        final data = <String, dynamic>{...pm, 'action': a};
        pendingOpen = data;
        openListener?.call(data);
      }
      return;
    }
    final pm = _parse(r.payload);
    if (pm != null && pm['k'] != null && (a == null || a.isEmpty)) {
      pendingOpen = pm;
      openListener?.call(pm);
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
    String? customPath;
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      tone = p.getString('set_incoming_tone') ?? 'system';
      customPath = p.getString('set_incoming_custom');
    } catch (_) {}
    const builtIn = {
      'classic', 'chime', 'marimba', 'digital', 'pulse', 'bell', 'soft',
    };
    final useRaw = builtIn.contains(tone);
    final custom = tone == 'custom' &&
        customPath != null &&
        File(customPath).existsSync();
    var accent = 0xFF009688;
    try {
      final p = await SharedPreferences.getInstance();
      accent = p.getInt('set_accent') ?? accent;
    } catch (_) {}
    final bigIcon = await _photo(data['caller_photo']?.toString())
        .timeout(const Duration(seconds: 4), onTimeout: () => null);
    await _plugin.show(
      _id,
      name,
      video ? 'Incoming video call' : 'Incoming voice call',
      NotificationDetails(
        android: AndroidNotificationDetails(
          custom
              ? 'incoming_calls_silent_v1'
              : (useRaw ? 'incoming_calls_v3_$tone' : 'incoming_calls_v2'),
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
          playSound: !custom,
          sound: custom ? null : useRaw
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

  /// Your own ringtone while the app is closed. Plays at most 30 seconds
  /// and stops when the call is answered, declined or gone.
  static Future<void> playCustomRingtone() async {
    ap.AudioPlayer? player;
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      if ((p.getString('set_incoming_tone') ?? 'system') != 'custom') return;
      final path = p.getString('set_incoming_custom');
      if (path == null || !File(path).existsSync()) return;
      player = ap.AudioPlayer();
      await player.setAudioContext(ap.AudioContext(
        android: ap.AudioContextAndroid(
          contentType: ap.AndroidContentType.sonification,
          usageType: ap.AndroidUsageType.notificationRingtone,
          audioFocus: ap.AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
      await player.setReleaseMode(ap.ReleaseMode.loop);
      await player.play(ap.DeviceFileSource(path), volume: 1.0);
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        await p.reload();
        if ((p.getInt(_kRing) ?? 0) == 0) break;
      }
    } catch (e) {
      debugPrint('RING custom: $e');
    } finally {
      try {
        await player?.stop();
        await player?.dispose();
      } catch (_) {}
    }
  }

  /// Chat, missed call or friend request alert (app closed or in background).
  static Future<void> showInfo(Map<String, dynamic> data) async {
    try {
      await _showInfoPrepared(data).timeout(const Duration(seconds: 8));
    } catch (_) {
      await _showInfoFallback(data);
    }
  }

  /// Used when decrypting takes too long: still shows the alert, but never
  /// the text of an encrypted message, and never for a muted chat.
  static Future<void> _showInfoFallback(Map<String, dynamic> data) async {
    try {
      const calls = {'missed_call', 'friend_request', 'group_call'};
      final kind = data['kind']?.toString() ?? '';
      var d = data;
      if (!calls.contains(kind)) {
        final gid = data['group_id']?.toString() ?? '';
        final uid = data['from_uid']?.toString() ?? '';
        final key =
            (kind == 'group_chat' && gid.isNotEmpty) ? 'g:$gid' : 'u:$uid';
        final p = await SharedPreferences.getInstance();
        await p.reload();
        final muted = p.getStringList('muted_chats') ?? const <String>[];
        if (muted.contains(key)) return;
        if (E2eeService.isEncryptedText(data['text']?.toString())) {
          d = {...data, 'text': 'New message'};
        }
      }
      await _showInfoRaw(d);
    } catch (_) {}
  }

  static Future<void> _showInfoPrepared(Map<String, dynamic> data) async {
    try {
      const calls = {'missed_call', 'friend_request', 'group_call'};
      final kind = data['kind']?.toString() ?? '';
      if (!calls.contains(kind)) {
        final gid = data['group_id']?.toString() ?? '';
        final uid = data['from_uid']?.toString() ?? '';
        final key =
            (kind == 'group_chat' && gid.isNotEmpty) ? 'g:$gid' : 'u:$uid';
        final p = await SharedPreferences.getInstance();
        await p.reload();
        final muted = p.getStringList('muted_chats') ?? const <String>[];
        if (muted.contains(key)) return;
        final lockedList = p.getStringList('locked_chats') ?? const <String>[];
        if (lockedList.contains(key)) {
          data = {...data, 'text': 'New message'};
        } else if (E2eeService.isEncryptedText(data['text']?.toString())) {
          try {
            await Supabase.initialize(
              url: AppConfig.supabaseUrl,
              anonKey: AppConfig.supabaseAnonKey,
            );
          } catch (_) {}
          for (var i = 0;
              i < 6 && Supabase.instance.client.auth.currentUser == null;
              i++) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
          final raw = data['text'].toString();
          final dec = (kind == 'group_chat' && gid.isNotEmpty)
              ? await E2eeService.decryptGroupText(
                  gid, p.getString('my_uid_${Supabase.instance.client.auth.currentUser?.id ?? ''}') ?? '', raw)
              : await E2eeService.decryptPeerText(uid, raw);
          data = {...data, 'text': dec};
        }
      }
    } catch (_) {}
    await _showInfoRaw(data);
  }

  static Future<void> _showInfoRaw(Map<String, dynamic> data) async {
    try {
      await _init();
      final kind = data['kind']?.toString() ?? '';
      final uid = data['from_uid']?.toString() ?? '';
      final gid = data['group_id']?.toString() ?? '';
      final name = data['from_name']?.toString() ?? 'QualityTime';
      final text = data['text']?.toString() ?? '';
      final video = data['video']?.toString() == 'true';
      var accent = 0xFF009688;
      try {
        final p = await SharedPreferences.getInstance();
        accent = p.getInt('set_accent') ?? accent;
      } catch (_) {}
      final id = 10000 + ((kind + uid + gid).hashCode & 0xFFFFF);
      final canReply = kind == 'chat' || kind == 'group_chat';
      await _plugin.show(
        id,
        name,
        text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'messages_v1',
            'Messages and alerts',
            channelDescription:
                'New chats, missed calls and friend requests',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            color: Color(accent),
            styleInformation: BigTextStyleInformation(text),
            showWhen: true,
            timeoutAfter: kind == 'group_call' ? 600000 : null,
            actions: canReply
                ? const <AndroidNotificationAction>[
                    AndroidNotificationAction(
                      'reply',
                      'Reply',
                      showsUserInterface: false,
                      cancelNotification: false,
                      inputs: <AndroidNotificationActionInput>[
                        AndroidNotificationActionInput(
                            label: 'Type a message'),
                      ],
                    ),
                    AndroidNotificationAction(
                      'markread',
                      'Mark as read',
                      showsUserInterface: false,
                    ),
                    AndroidNotificationAction(
                      'call',
                      'Call',
                      showsUserInterface: true,
                    ),
                  ]
                : null,
          ),
        ),
        payload: jsonEncode({'k': kind, 'u': uid, 'g': gid, 'v': video, 'n': name, 't': text}),
      );
    } catch (e) {
      debugPrint('INFO: $e');
    }
  }

  static Future<void> _oldShowInfo(Map<String, dynamic> data) async {
    try {
      await _init();
      final kind = data['kind']?.toString() ?? '';
      final uid = data['from_uid']?.toString() ?? '';
      final gid = data['group_id']?.toString() ?? '';
      final name = data['from_name']?.toString() ?? 'QualityTime';
      final text = data['text']?.toString() ?? '';
      var accent = 0xFF009688;
      try {
        final p = await SharedPreferences.getInstance();
        accent = p.getInt('set_accent') ?? accent;
      } catch (_) {}
      final id = 10000 + ((kind + uid + gid).hashCode & 0xFFFFF);
      await _plugin.show(
        id,
        name,
        text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'messages_v1',
            'Messages and alerts',
            channelDescription:
                'New chats, missed calls and friend requests',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            color: Color(accent),
            styleInformation: BigTextStyleInformation(text),
            showWhen: true,
          ),
        ),
        payload: jsonEncode({'k': kind, 'u': uid, 'g': gid}),
      );
    } catch (e) {
      debugPrint('INFO: $e');
    }
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