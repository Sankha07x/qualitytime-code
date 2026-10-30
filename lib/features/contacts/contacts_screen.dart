import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide HapticFeedback;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'contact_controller.dart';
import 'contact_model.dart';
import '../../utils/user_avatar.dart';
import '../../core/auth/profile_service.dart';
import '../profile/profile_screen.dart';
import 'contact_detail_screen.dart';
import 'add_contact_screen.dart';
import '../call/call_controller.dart';
import '../call/call_screen.dart';
import '../call/active_call.dart';
import '../call/incoming_call_screen.dart';
import '../../core/signaling/incoming_call_service.dart';
import '../../core/notifications/callkit_service.dart';
import '../../core/notifications/call_notification.dart';
import '../../core/audio/tone_player.dart';
import '../call/call_log/call_log_controller.dart';
import '../call/call_log/call_log_panel.dart';
import '../../core/presence/presence_service.dart';
import '../../utils/net_status.dart';
import 'notifications_screen.dart';
import '../chat/chat_inbox_screen.dart';
import '../chat/chat_screen.dart';
import 'dart:io' show File;
import '../../utils/settings/app_settings.dart';
import '../../utils/haptics.dart';
import '../../utils/settings/chat_prefs.dart';
import '../../core/security/e2ee_service.dart';
import 'dart:ui' show ImageFilter;
import '../../utils/glass.dart';
import '../settings/settings_screen.dart';
import '../groups/groups_screen.dart';
import '../groups/group_controller.dart';
import '../groups/group_call_screen.dart';
import '../groups/group_chat_screen.dart';
import '../groups/group_status.dart';
import '../../utils/settings/contact_quality_prefs.dart';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import '../../config/app_colors.dart';
import '../chat/photo_bubble.dart';
import '../chat/locked_chat_view.dart';
import '../chat/chat_service.dart';
import '../voice/voice_service.dart';
import '../chat/voice_bubble.dart';
import '../groups/group_chat_service.dart';
import '../groups/group_detail_screen.dart';

class _ContactOrGroupItem {
  final ContactModel? contact;
  final GroupModel? group;
  _ContactOrGroupItem.contact(this.contact) : group = null;
  _ContactOrGroupItem.group(this.group) : contact = null;
  bool get isGroup => group != null;
  String get id => isGroup ? group!.id : contact!.uid;
  String get name => isGroup ? group!.name : contact!.displayName;
}

class _InlineItem {
  final DateTime at;
  final ChatMessage? chat;
  final VoiceMessage? voice;
  _InlineItem({required this.at, this.chat, this.voice});
}

class ContactsScreen extends StatefulWidget {
  final ContactController contactController;
  final String myUid;
  final VoidCallback? onIdChanged;

  const ContactsScreen({
    super.key,
    required this.contactController,
    required this.myUid,
    this.onIdChanged,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with WidgetsBindingObserver {
  late final IncomingCallService _service;
  StreamSubscription<IncomingCall>? _ringSub;
  StreamSubscription<String>? _cancelSub;
  StreamSubscription<GroupIncoming>? _gringSub;
  StreamSubscription<AcceptedCall>? _acceptSub;
  StreamSubscription<DeclinedCall>? _declineSub;

  bool _busy = false;
  String? _incomingSession;
  bool _waiting = false;
  String? _activeSession;

  // Simultaneous calls: who I'm calling, and a ring I'll answer instead.
  String? _callingUid;
  CallController? _outgoingController;
  IncomingCall? _yieldTo;
  final _tones = TonePlayer();
  final _log = CallLogController();
  String? _cancelledSession;
  bool _cover = !kIsWeb;
  MyProfile? _me;
  final _profiles = ProfileService();
  late final PresenceService _presence;

  bool _wasOnline = true;
  bool _unreadReady = false;
  Timer? _groupPoll;
  Timer? _unreadDebounce;

  // Unread chat messages per friend (waiting in the cloud).
  final _unread = ValueNotifier<Map<String, int>>({});
  final _preview = ValueNotifier<Map<String, String>>({});
  final _missed = ValueNotifier<List<Map<String, dynamic>>>([]);
  RealtimeChannel? _chatCh;
  late final GroupController _groupController = GroupController(widget.myUid);
  final Map<String, String> _callTileStatus = {};
  int? _selectedTileIndex;
  _ContactOrGroupItem? _selectedItem;

  ChatService? _inlineChatService;
  GroupChatService? _inlineGroupChatService;
  VoiceService? _inlineVoiceService;
  final VoicePlayerController _inlineVoicePlayer = VoicePlayerController();

  final TextEditingController _inlineTextCtrl = TextEditingController();
  bool _inlineHasText = false;
  bool _recordingVoice = false;
  int _voiceSecs = 0;
  Timer? _voiceTimer;

  String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Tells senders their messages reached this phone (second grey tick).
  Future<void> _markDelivered() async {
    try {
      await Supabase.instance.client
          .from('chat_messages')
          .update({'delivered_at': DateTime.now().toUtc().toIso8601String()})
          .eq('to_uid', widget.myUid)
          .isFilter('delivered_at', null);
    } catch (_) {}
  }

  Future<void> _loadMissed() async {
    try {
      final rows = await Supabase.instance.client
          .from('app_notifications')
          .select()
          .eq('to_uid', widget.myUid)
          .order('created_at', ascending: false)
          .limit(30);
      if (mounted) {
        _missed.value = [
          for (final r in rows as List) Map<String, dynamic>.from(r),
        ];
      }
    } catch (_) {}
  }

  Future<void> _markMissedSeen() async {
    try {
      await Supabase.instance.client
          .from('app_notifications')
          .update({'seen': true})
          .eq('to_uid', widget.myUid)
          .eq('seen', false);
    } catch (_) {}
    _loadMissed();
  }

  /// Tells the callee's phone (and Notifications page) about a missed call.
  Future<void> _notifyMissed(String toUid, bool video) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-notify-push',
        body: {'kind': 'missed_call', 'to_uid': toUid, 'video': video},
      );
    } catch (e) {
      debugPrint('MISSED push failed: $e');
    }
  }

  Future<void> _loadUnread() async {
    _markDelivered();
    try {
      final rows = await Supabase.instance.client
          .from('chat_messages')
          .select('from_uid, kind, body')
          .eq('to_uid', widget.myUid)
          .neq('kind', 'delete')
          .neq('kind', 'edit')
          .isFilter('read_at', null)
          .order('created_at');
      final m = <String, int>{};
      final pv = <String, String>{};
      for (final r in rows as List) {
        final u = r['from_uid'] as String;
        m[u] = (m[u] ?? 0) + 1;
        pv[u] = r['kind'] == 'file'
            ? '📎 File'
            : await E2eeService.decryptPeerText(
                u, (r['body'] ?? '').toString());
      }
      if (mounted) {
        final before = _unread.value.values.fold<int>(0, (a, b) => a + b);
        final after = m.values.fold<int>(0, (a, b) => a + b);
        if (_unreadReady && after > before) Haptics.medium();
        _unreadReady = true;
        _preview.value = pv;
        _unread.value = m;
      }
    } catch (_) {}
    _loadLatestPreviews();
  }

  Future<void> _loadLatestPreviews() async {
    try {
      final me = widget.myUid;
      final db = Supabase.instance.client;
      final contacts = widget.contactController.contacts.value;
      final groups = _groupController.groups.value;
      final pv = <String, String>{};
      final unread = <String, int>{};

      try {
        final rows = await db
            .from('chat_messages')
            .select('from_uid, kind, body, file_name, created_at')
            .eq('to_uid', me)
            .neq('kind', 'delete')
            .neq('kind', 'edit')
            .isFilter('read_at', null)
            .order('created_at');
        for (final r in rows as List) {
          final u = (r['from_uid'] ?? '').toString();
          unread[u] = (unread[u] ?? 0) + 1;
          final kind = r['kind']?.toString() ?? 'text';
          final fn = r['file_name']?.toString();
          if (kind == 'file') {
            pv[u] = (fn != null && isImageName(fn)) ? 'Photo' : (fn ?? 'Photo');
          } else {
            final raw = (r['body'] ?? '').toString();
            pv[u] = await E2eeService.decryptPeerText(u, raw);
          }
        }
      } catch (_) {}

      try {
        final vrows = await db
            .from('voice_messages')
            .select('from_uid, to_uid, view_once, played_at')
            .eq('to_uid', me)
            .isFilter('played_at', null);
        for (final r in vrows as List) {
          final u = (r['from_uid'] ?? '').toString();
          unread[u] = (unread[u] ?? 0) + 1;
          final vo = r['view_once'] == true;
          pv[u] = vo ? 'View once' : 'Voice message';
        }
      } catch (_) {}

      final dir = await getApplicationDocumentsDirectory();
      for (final c in contacts) {
        if (!pv.containsKey(c.uid)) {
          try {
            final f = File('${dir.path}/chat_${_safe(c.uid)}.json');
            if (await f.exists()) {
              final list = jsonDecode(await f.readAsString()) as List;
              if (list.isNotEmpty) {
                final last = list.last as Map;
                final kind = last['kind']?.toString();
                final fn = last['fileName']?.toString();
                if (kind == 'file') {
                  pv[c.uid] = (fn != null && isImageName(fn)) ? 'Photo' : (fn ?? 'Photo');
                } else {
                  pv[c.uid] = (last['body'] ?? '').toString();
                }
              }
            }
          } catch (_) {}
        }
        if (ChatPrefs.locked.value.contains('u:${c.uid}')) {
          pv[c.uid] = 'Locked chat';
        }
      }

      for (final g in groups) {
        if (ChatPrefs.locked.value.contains('g:${g.id}')) {
          pv[g.id] = 'Locked chat';
          continue;
        }
        try {
          final grows = await db
              .from('group_messages')
              .select('body, from_uid, created_at')
              .eq('group_id', g.id)
              .order('created_at', ascending: false)
              .limit(1);
          if (grows is List && grows.isNotEmpty) {
            final r = grows.first as Map;
            var rawBody = (r['body'] ?? '').toString();
            String text;
            if (E2eeService.isEncryptedText(rawBody)) {
              text = await E2eeService.decryptGroupText(g.id, me, rawBody);
            } else {
              text = rawBody;
            }
            pv[g.id] = text;
          }
        } catch (_) {}
      }

      if (mounted) {
        _preview.value = {..._preview.value, ...pv};
        _unread.value = {..._unread.value, ...unread};
      }
    } catch (_) {}
  }

  /// Back online: refresh contacts, names, photos and my profile.
  void _onNet() {
    final on = NetStatus.online.value;
    if (on && !_wasOnline) {
      widget.contactController
          .syncWithCloud()
          .then((_) => widget.contactController.refreshProfiles());
      _loadMe();
    }
    _wasOnline = on;
  }

  void _watchContacts() => _presence
      .watch(widget.contactController.contacts.value.map((c) => c.uid));

  Future<void> _loadMe() async {
    try {
      final p = await _profiles.load();
      if (mounted) setState(() => _me = p);
    } catch (_) {}
  }

  Future<void> _openProfile() async {
    final idChanged = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (!mounted) return;
    _loadMe();
    if (idChanged == true) widget.onIdChanged?.call();
  }

  void _openContact(ContactModel c) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactDetailScreen(
          contact: c,
          contactController: widget.contactController,
          log: _log,
          onCall: (video) {
            Navigator.of(context).pop();
            _callContact(c, video: video);
          },
        ),
      ),
    );
  }

  /// Answer tapped on the notification: go straight into the call.
  Future<void> _answerNow() async {
    if (_busy || !mounted || CallNotification.pendingAction != 'answer') return;
    final c = CallNotification.takeCall();
    if (c == null) return;
    CallNotification.pendingAction = null;
    final session = c['s']?.toString() ?? '';
    if (session.isEmpty) return;
    final uid = c['u']?.toString() ?? '';
    final video = c['v'] == true;
    if (session.startsWith('group_')) {
      await _answerGroupFromPush(session.substring(6), video);
      return;
    }
    // Voice call answered from the notification: stay in the background.
    if (!video) {
      Future.delayed(const Duration(milliseconds: 600), () {
        const MethodChannel('qt/pip').invokeMethod('leave').catchError((_) {});
      });
    }
    final saved = widget.contactController.contacts.value
        .any((x) => x.uid == uid);
    final name =
        saved ? _nameFor(uid) : (c['n']?.toString() ?? _nameFor(uid));
    final p = c['p']?.toString() ?? '';
    final photo =
        p.isNotEmpty ? p : widget.contactController.photos.value[uid];
    _busy = true;
    CallNotification.cancel();
    final controller = CallController();
    try {
      await _runCall(
        controller,
        name: name,
        photo: photo,
        outgoing: false,
        sessionId: session,
        video: video,
      );
    } finally {
      _busy = false;
    }
    _logCall(
      uid: uid,
      outgoing: false,
      video: video,
      result: CallResult.answered,
      seconds: controller.connectedSeconds,
    );
    if (_cover) SystemNavigator.pop();
  }

  /// "Group call is running" notification tapped: join only if still live.
  Future<void> _openLiveGroup(String gid) async {
    if (gid.isEmpty || !mounted || _busy) return;
    try {
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 45))
          .toIso8601String();
      final live = await Supabase.instance.client
          .from('live_group_calls')
          .select('video')
          .eq('group_id', gid)
          .gte('updated_at', since)
          .maybeSingle();
      if (!mounted) return;
      if (live == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That group call has ended.')),
        );
        return;
      }
      await _answerGroupFromPush(gid, live['video'] == true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join. Check your internet.')),
        );
      }
    }
  }

  Future<void> _answerGroupFromPush(String gid, bool video) async {
    _busy = true;
    CallNotification.cancel();
    try {
      final r = await Supabase.instance.client
          .from('groups')
          .select('name, emoji, color, mode')
          .eq('id', gid)
          .maybeSingle();
      if (r != null && mounted) {
        await _openGroupCall(
          gid,
          r['name'].toString(),
          (r['emoji'] ?? '👥').toString(),
          (r['color'] as num?)?.toInt() ?? 0xFF0D9488,
          (r['mode'] ?? 'friends').toString(),
          video,
        );
      }
    } finally {
      _busy = false;
    }
    if (_cover) SystemNavigator.pop();
  }

  Future<void> _initCover() async {
    if (kIsWeb) return;
    await CallNotification.checkLaunchAction();
    if (CallNotification.pendingAction == 'answer' &&
        CallNotification.pendingCall != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _answerNow());
      return;
    }
    final rang = await CallNotification.recentlyRang();
    if (!mounted) return;
    if (!rang) {
      setState(() => _cover = false);
      return;
    }
    _uncoverLater();
  }

  void _uncoverLater() {
    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && _cover && _incomingSession == null && !_busy) {
        setState(() => _cover = false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && ActiveCall.running == null) {
      _presence.setVisible(false);
    } else if (state == AppLifecycleState.resumed) {
      _presence.setVisible(true);
      widget.contactController.refreshFriends();
    }
    if (state != AppLifecycleState.resumed || kIsWeb) return;
    CallNotification.recentlyRang().then((rang) {
      if (rang && mounted && !_busy && !_cover) {
        setState(() => _cover = true);
        _uncoverLater();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCover().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleOpenTap());
    });
    CallNotification.openListener = _handleOpenTap;
    ChatScreen.startCall = (uid, name, video) {
      final c = widget.contactController.contacts.value
              .where((x) => x.uid == uid)
              .firstOrNull ??
          ContactModel(uid: uid, displayName: name, addedAt: DateTime.now());
      _callContact(c, video: video);
    };
    _loadMissed();
    CallNotification.actionListener = (a) {
      if (_incomingSession != null && mounted) {
        CallNotification.pendingAction = null;
        CallNotification.pendingCall = null;
        Navigator.of(context).pop(a == 'answer');
      } else {
        _answerNow();
      }
    };
    widget.contactController.myUid = widget.myUid;
    ContactController.current = widget.contactController;
    widget.contactController
        .syncWithCloud()
        .then((_) => widget.contactController.refreshProfiles())
        .then((_) => widget.contactController.startFriends());
    NetStatus.online.addListener(_onNet);
    _loadMe();
    _presence = PresenceService(widget.myUid)..start();
    GroupStatus.refresh(widget.myUid);
    _groupPoll = Timer.periodic(const Duration(seconds: 15),
        (_) {
      if (NetStatus.online.value) GroupStatus.refresh(widget.myUid);
    });
    _loadUnread();
    _chatCh = Supabase.instance.client
        .channel('chat_unread')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) {
            _unreadDebounce?.cancel();
            _unreadDebounce =
                Timer(const Duration(milliseconds: 400), _loadUnread);
          },
        )
        .subscribe();
    widget.contactController.contacts.addListener(_watchContacts);
    _watchContacts();
    _groupController.start();
    _groupController.groups.addListener(_onGroupsChanged);
    _inlineTextCtrl.addListener(_onInlineTextChanged);
    _service = IncomingCallService(widget.myUid);
    _service.start();
    _ringSub = _service.onRing.listen(_onRing);
    _cancelSub = _service.onCancel.listen(_onCancel);
    _gringSub = _service.onGroupRing.listen(_onGroupRing);

    if (!kIsWeb) {
      CallKitService.instance.start();
      _acceptSub =
          CallKitService.instance.onAccepted.listen(_onCallKitAccepted);
      CallKitService.instance.emitAcceptedFromActiveCalls();
      _declineSub =
          CallKitService.instance.onDeclined.listen(_onCallKitDeclined);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallNotification.actionListener = null;
    widget.contactController.contacts.removeListener(_watchContacts);
    NetStatus.online.removeListener(_onNet);
    _groupPoll?.cancel();
    _unreadDebounce?.cancel();
    _presence.dispose();
    _chatCh?.unsubscribe();
    _unread.dispose();
    _preview.dispose();
    _missed.dispose();
    CallNotification.openListener = null;
    ChatScreen.startCall = null;
    _ringSub?.cancel();
    _cancelSub?.cancel();
    _gringSub?.cancel();
    _acceptSub?.cancel();
    _declineSub?.cancel();
    _log.dispose();
    _tones.dispose();
    _service.dispose();
    _groupController.groups.removeListener(_onGroupsChanged);
    _groupController.dispose();
    _inlineTextCtrl.removeListener(_onInlineTextChanged);
    _inlineTextCtrl.dispose();
    _voiceTimer?.cancel();
    _disposeInlineChat();
    _inlineVoicePlayer.dispose();
    super.dispose();
  }

  void _onInlineTextChanged() {
    final h = _inlineTextCtrl.text.trim().isNotEmpty;
    if (h != _inlineHasText && mounted) {
      setState(() => _inlineHasText = h);
    }
  }

  void _onGroupsChanged() {
    _loadLatestPreviews();
    if (mounted) setState(() {});
  }

  Future<void> _logCall({
    required String uid,
    required bool outgoing,
    required bool video,
    required CallResult result,
    int seconds = 0,
  }) async {
    if (uid.isEmpty) return;
    await _log.add(CallLogEntry(
      uid: uid,
      outgoing: outgoing,
      video: video,
      result: result,
      time: DateTime.now(),
      seconds: seconds,
    ));
  }

  Future<void> _addFromLog(String uid) async {
    String? err;
    try {
      err = await widget.contactController.sendFriendRequest(uid);
    } catch (_) {
      err = 'Could not send. Check your internet.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Friend request sent')),
    );
  }

  Future<bool> _friendSafe(String uid) async {
    try {
      return await widget.contactController.isFriend(uid);
    } catch (_) {
      return _isSaved(uid);
    }
  }

  bool _isSaved(String uid) =>
      widget.contactController.contacts.value.any((c) => c.uid == uid);

  void _callBack(CallLogEntry e) {
    final contact = widget.contactController.contacts.value
            .where((c) => c.uid == e.uid)
            .firstOrNull ??
        ContactModel(
          uid: e.uid,
          displayName: _nameFor(e.uid),
          addedAt: DateTime.now(),
        );
    _callContact(contact, video: e.video);
  }

  /// Both peers join the same channel; sorted UIDs make the id identical.
  String _sessionIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  /// The other person's UID, taken from the shared session id.
  String _peerFromSession(String s) {
    final me = widget.myUid;
    if (s.startsWith('${me}_')) return s.substring(me.length + 1);
    if (s.endsWith('_$me')) return s.substring(0, s.length - me.length - 1);
    return '';
  }

  String _nameFor(String uid) {
    for (final c in widget.contactController.contacts.value) {
      if (c.uid == uid) return c.displayName;
    }
    return uid.length > 8 ? uid.substring(0, 8) : uid;
  }

  /// A second person calls while I am on a call: the first call goes on
  /// hold, the new call rings, and the first call comes back when it ends.
  Future<void> _answerWaiting(IncomingCall call, CallController first) async {
    _waiting = true;
    final wasHeld = first.onHold.value;
    try {
      if (!await widget.contactController.isFriend(call.fromUid)) {
        _service.sendBusy(toUid: call.fromUid, sessionId: call.sessionId);
        return;
      }
      if (!mounted) return;
      _incomingSession = call.sessionId;
      _service.sendRinging(toUid: call.fromUid, sessionId: call.sessionId);
      if (!kIsWeb) CallNotification.cancel();
      if (!wasHeld) await first.toggleHold();
      final photo = widget.contactController.photos.value[call.fromUid];
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => IncomingCallScreen(
            photoUrl: photo,
            callerName: _nameFor(call.fromUid),
            video: call.video,
          ),
        ),
      );
      _incomingSession = null;
      if (accepted == true && mounted) {
        final controller = CallController();
        await _runCallInner(
          controller,
          name: _nameFor(call.fromUid),
          photo: photo,
          outgoing: false,
          sessionId: call.sessionId,
          video: call.video,
        );
        _logCall(
          uid: call.fromUid,
          outgoing: false,
          video: call.video,
          result: CallResult.answered,
          seconds: controller.connectedSeconds,
        );
      } else {
        _logCall(
          uid: call.fromUid,
          outgoing: false,
          video: call.video,
          result: _cancelledSession == call.sessionId
              ? CallResult.missed
              : CallResult.declined,
        );
        _service.sendDecline(toUid: call.fromUid, sessionId: call.sessionId);
      }
    } finally {
      _incomingSession = null;
      _cancelledSession = null;
      _waiting = false;
      if (!wasHeld &&
          first.phase.value == CallPhase.active &&
          first.onHold.value) {
        await first.toggleHold();
      }
    }
  }

  Future<void> _onRing(IncomingCall call) async {
    // Both called at the same moment: the higher UID quietly answers.
    if (_busy &&
        _callingUid == call.fromUid &&
        _yieldTo == null &&
        widget.myUid.compareTo(call.fromUid) > 0) {
      _yieldTo = call;
      final c = _outgoingController;
      if (c != null) {
        c.silentEnd = true;
        try {
          await c.endCall(notifyPeer: false);
        } catch (_) {}
      }
      if (mounted) Navigator.of(context).pop(); // closes my outgoing screen
      return;
    }
    if (_busy && _incomingSession == call.sessionId) {
      _service.sendRinging(toUid: call.fromUid, sessionId: call.sessionId);
      return;
    }
    if (!mounted) return;
    if (_busy) {
      if (call.sessionId == _activeSession) return;
      if (call.fromUid != _callingUid) {
        if (_waiting) {
          if (call.sessionId != _incomingSession) {
            _service.sendBusy(toUid: call.fromUid, sessionId: call.sessionId);
          }
          return;
        }
        final run = ActiveCall.running;
        if (run != null &&
            run.phase.value == CallPhase.active &&
            _incomingSession == null) {
          _answerWaiting(call, run);
          return;
        }
        _service.sendBusy(toUid: call.fromUid, sessionId: call.sessionId);
        if (!kIsWeb) CallKitService.instance.endCall(call.sessionId);
      }
      return;
    }
    _busy = true;
    if (!await _friendSafe(call.fromUid)) {
      _busy = false;
      return;
    }
    _incomingSession = call.sessionId;
    _service.sendRinging(toUid: call.fromUid, sessionId: call.sessionId);
    if (!kIsWeb) CallNotification.cancel();
    try {
      final cached = widget.contactController.photos.value[call.fromUid];
      final photo = cached != null
          ? (cached.isEmpty ? null : cached)
          : await widget.contactController
              .fetchPhoto(call.fromUid)
              .timeout(const Duration(milliseconds: 500),
                  onTimeout: () => null);
      if (!mounted) return;
      final act = CallNotification.takeAction();
      final accepted = act != null
          ? act == 'answer'
          : await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => IncomingCallScreen(
            photoUrl: photo,
            callerName: _nameFor(call.fromUid),
            video: call.video,
          ),
        ),
      );
      _incomingSession = null;

      if (accepted != true) {
        _logCall(
          uid: call.fromUid,
          outgoing: false,
          video: call.video,
          result: _cancelledSession == call.sessionId
              ? CallResult.missed
              : CallResult.declined,
        );
        _service.sendDecline(toUid: call.fromUid, sessionId: call.sessionId);
      }

      if (accepted == true && mounted) {
        final controller = CallController();
        await _runCall(
          controller,
          name: _nameFor(call.fromUid),
          photo: photo,
          outgoing: false,
          sessionId: call.sessionId,
          video: call.video,
        );
        _logCall(
          uid: call.fromUid,
          outgoing: false,
          video: call.video,
          result: CallResult.answered,
          seconds: controller.connectedSeconds,
        );
      }
    } finally {
      _incomingSession = null;
      _cancelledSession = null;
      _busy = false;
      if (_cover) SystemNavigator.pop();
    }
  }

  Future<void> _openGroupCall(String id, String name, String emoji, int color,
      String mode, bool video) async {
    final gc = GroupController(widget.myUid);
    await gc.refresh();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          groupId: id,
          groupName: name,
          video: video,
          emoji: emoji,
          color: color,
          mode: mode,
          groupController: gc,
          contactController: widget.contactController,
          myUid: widget.myUid,
        ),
      ),
    );
    gc.dispose();
  }

  /// Someone started a group call: show the incoming screen.
  Future<void> _onGroupRing(GroupIncoming g) async {
    if (_busy || !mounted || g.groupId.isEmpty) {
      if (_busy && g.fromUid.isNotEmpty) {
        _service.sendBusy(
          toUid: g.fromUid,
          sessionId: 'group_${g.groupId}_${widget.myUid}',
        );
      }
      return;
    }
    final sid = 'group_${g.groupId}';
    _busy = true;
    _incomingSession = sid;
    if (!kIsWeb) CallNotification.cancel();
    if (g.fromUid.isNotEmpty) {
      _service.sendRinging(toUid: g.fromUid, sessionId: '${sid}_${widget.myUid}');
    }
    Timer? giveUp;
    try {
      giveUp = Timer(const Duration(seconds: 30), () {
        if (_incomingSession == sid && mounted) {
          Navigator.of(context).pop(false);
        }
      });
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => IncomingCallScreen(
            photoUrl: null,
            callerName: '${g.emoji} ${g.groupName}',
            video: g.video,
          ),
        ),
      );
      giveUp.cancel();
      _incomingSession = null;
      if (!kIsWeb) CallKitService.instance.endCall(sid);
      if (accepted == true && mounted) {
        await _openGroupCall(
            g.groupId, g.groupName, g.emoji, g.color, g.mode, g.video);
      } else if (accepted == false && g.fromUid.isNotEmpty) {
        _service.sendDecline(toUid: g.fromUid, sessionId: '${sid}_${widget.myUid}');
      }
    } finally {
      giveUp?.cancel();
      _incomingSession = null;
      _busy = false;
    }
  }

  /// User tapped Accept on the native full-screen ringing UI.
  Future<void> _onCallKitAccepted(AcceptedCall call) async {
    if (!mounted) return;
    // The app's own incoming screen is already up for this call: accept it.
    if (_incomingSession == call.sessionId) {
      Navigator.of(context).pop(true);
      CallKitService.instance.endCall(call.sessionId);
      return;
    }
    if (_busy) return;
    if (call.sessionId.startsWith('group_')) {
      _busy = true;
      CallKitService.instance.endCall(call.sessionId);
      try {
        final gid = call.sessionId.substring(6);
        final r = await Supabase.instance.client
            .from('groups')
            .select('name, emoji, color, mode')
            .eq('id', gid)
            .maybeSingle();
        if (r != null && mounted) {
          await _openGroupCall(
            gid,
            r['name'].toString(),
            (r['emoji'] ?? '👥').toString(),
            (r['color'] as num?)?.toInt() ?? 0xFF0D9488,
            (r['mode'] ?? 'friends').toString(),
            call.video,
          );
        }
      } finally {
        _busy = false;
      }
      SystemNavigator.pop();
      return;
    }
    _busy = true;
    CallKitService.instance.endCall(call.sessionId);
    final controller = CallController();
    try {
      await _runCall(
        controller,
        name: _nameFor(call.callerUid),
        photo: widget.contactController.photos.value[call.callerUid],
        outgoing: false,
        sessionId: call.sessionId,
        video: call.video,
      );
    } finally {
      _busy = false;
    }
    await _logCall(
      uid: call.callerUid,
      outgoing: false,
      video: call.video,
      result: CallResult.answered,
      seconds: controller.connectedSeconds,
    );
    // Call was answered from the native ringing screen: close the app after it.
    SystemNavigator.pop();
  }

  /// User tapped Decline on the native ringing UI.
  void _onCallKitDeclined(DeclinedCall call) {
    if (_incomingSession == call.sessionId && mounted) {
      Navigator.of(context).pop(false); // _onRing sends the decline
      return;
    }
    if (call.sessionId.startsWith('group_')) {
      if (call.callerUid.isNotEmpty) {
        _service.sendDecline(toUid: call.callerUid, sessionId: '${call.sessionId}_${widget.myUid}');
      }
      return;
    }
    if (call.callerUid.isNotEmpty) {
      _logCall(
        uid: call.callerUid,
        outgoing: false,
        video: false,
        result: CallResult.declined,
      );
      _service.sendDecline(toUid: call.callerUid, sessionId: call.sessionId);
    }
  }

  void _onCancel(String sessionId) {
    if (!kIsWeb) {
      CallKitService.instance.endCall(sessionId);
      CallNotification.cancel();
    }
    if (_incomingSession == sessionId && mounted) {
      _cancelledSession = sessionId;
      Navigator.of(context).pop(false);
    }
  }

  /// Asks the server to send a push to the callee's phone, so it can ring
  /// even when the app is closed or locked. Never throws.
  Future<void> _sendCallPush(String toUid, {required bool video}) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'send-call-push',
        body: {
          'callee_uid': toUid,
          'call_type': video ? 'video' : 'voice',
        },
      );
      debugPrint('PUSH send result: ${res.data}');
    } catch (e) {
      debugPrint('PUSH send failed: $e');
    }
  }

  Future<void> _callContact(ContactModel contact, {required bool video}) async {
    if (_busy) return;
    if (!mounted) return;
    if (!NetStatus.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're offline. Can't call right now.")),
      );
      return;
    }
    _busy = true;
    if (!await _friendSafe(contact.uid)) {
      _busy = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can only call friends. Send a request first.'),
          ),
        );
      }
      return;
    }
    final sessionId = _sessionIdFor(widget.myUid, contact.uid);
    final controller = CallController();
    _callingUid = contact.uid;
    _outgoingController = controller;
    var wasDeclined = false;

    Timer? offlineTimer;
    Timer? ringTimeout;
    controller.phase.addListener(() {
      if (controller.phase.value == CallPhase.active) {
        offlineTimer?.cancel();
        ringTimeout?.cancel();
        _service.stopRingTimer();
        _tones.stopRingback();
      }
    });

    _service.startRinging(
      toUid: contact.uid,
      sessionId: sessionId,
      video: video,
    );
    _callTileStatus[contact.uid] = 'Calling';
    if (mounted) setState(() {});

    final declineSub = _service.onDecline.listen((s) async {
      if (s != sessionId || !mounted) return;
      controller.endLabel = 'Call declined';
      wasDeclined = true;
      _callTileStatus[contact.uid] = 'Declined';
      if (mounted) setState(() {});
      Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _callTileStatus.remove(contact.uid));
      });
      _tones.playBusy();
      await controller.endCall(notifyPeer: false);
    });

    final busySub = _service.onBusy.listen((s) async {
      if (s != sessionId || !mounted) return;
      final p = controller.phase.value;
      if (p == CallPhase.active ||
            p == CallPhase.ended ||
            controller.peerAnswered) {
          return;
        }
      controller.endLabel = 'On another call';
      _callTileStatus[contact.uid] = 'On another call';
      if (mounted) setState(() {});
      Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _callTileStatus.remove(contact.uid));
      });
      _tones.playBusy();
      await controller.endCall(notifyPeer: false);
    });

    final calleeOnline = _presence.online.value.contains(contact.uid);
    final hint = ValueNotifier<String?>(
      calleeOnline ? 'Ringing...' : 'Calling...',
    );
    var ringbackOn = false;
    void startRingback() {
      if (ringbackOn) return;
      ringbackOn = true;
      offlineTimer?.cancel();
      hint.value = 'Ringing...';
      _callTileStatus[contact.uid] = 'Ringing';
      if (mounted) setState(() {});
      _tones.playRingback(earpiece: !video);
      // Ringing stage: nobody picks up for 27 s, end the call.
      ringTimeout = Timer(const Duration(seconds: 27), () async {
        final p = controller.phase.value;
        if (p == CallPhase.active || p == CallPhase.ended) return;
        controller.endLabel = 'No answer';
        await controller.endCall(notifyPeer: false);
      });
    }

    if (calleeOnline) startRingback();
    final ringingSub = _service.onRinging.listen((s) {
      if (s == sessionId) startRingback();
    });
    // Calling stage: no ringing signal for 8 s, end the call as offline.
    offlineTimer = Timer(const Duration(seconds: 30), () async {
      if (ringbackOn ||
          controller.peerAnswered ||
          controller.phase.value != CallPhase.connecting) {
        return;
      }
      controller.endLabel = 'Offline. Their phone is not reachable.';
      await controller.endCall(notifyPeer: false);
    });

    // Wake the callee's phone if the app is closed (runs in background).
    _sendCallPush(contact.uid, video: video);

    try {
      await _runCall(
        controller,
        name: contact.displayName,
        photo: widget.contactController.photos.value[contact.uid],
        outgoing: true,
        sessionId: sessionId,
        video: video,
        hint: hint,
      );
    } finally {
      offlineTimer?.cancel();
      ringTimeout?.cancel();
      ringingSub.cancel();
      declineSub.cancel();
      busySub.cancel();
      _tones.stopRingback();
      await _service.stopRinging(toUid: contact.uid, sessionId: sessionId);
      _callingUid = null;
      _outgoingController = null;
      if (_yieldTo == null &&
          controller.connectedSeconds == 0 &&
          !wasDeclined &&
          !controller.peerAnswered) {
        _notifyMissed(contact.uid, video);
      }
      if (_yieldTo == null) {
        _logCall(
          uid: contact.uid,
          outgoing: true,
          video: video,
          result: controller.connectedSeconds > 0
              ? CallResult.answered
              : (wasDeclined ? CallResult.declined : CallResult.cancelled),
          seconds: controller.connectedSeconds,
        );
      }
      _busy = false;
    }

    // Simultaneous call: now answer the other person's call instead.
    final y = _yieldTo;
    _yieldTo = null;
    if (y != null && mounted) _answerYielded(y);
  }

  Future<void> _answerYielded(IncomingCall call) async {
    if (_busy) return;
    _busy = true;
    final controller = CallController();
    try {
      await _runCall(
        controller,
        name: _nameFor(call.fromUid),
        photo: widget.contactController.photos.value[call.fromUid],
        outgoing: false,
        sessionId: call.sessionId,
        video: call.video,
      );
    } finally {
      _busy = false;
    }
    _logCall(
      uid: call.fromUid,
      outgoing: false,
      video: call.video,
      result: CallResult.answered,
      seconds: controller.connectedSeconds,
    );
  }

  /// Shows the call screen. Back button = minimize (the call keeps running
  /// and a bar lets the user return). Returns when the call has ended.
  Future<void> _runCall(
    CallController controller, {
    required String name,
    String? photo,
    required bool outgoing,
    required String sessionId,
    required bool video,
    ValueListenable<String?>? hint,
  }) async {
    _activeSession = sessionId;
    try {
      await _runCallInner(
        controller,
        name: name,
        photo: photo,
        outgoing: outgoing,
        sessionId: sessionId,
        video: video,
        hint: hint,
      );
    } finally {
      if (_activeSession == sessionId) _activeSession = null;
    }
  }

  Future<void> _runCallInner(
    CallController controller, {
    required String name,
    String? photo,
    required bool outgoing,
    required String sessionId,
    required bool video,
    ValueListenable<String?>? hint,
  }) async {
    var resume = false;
    final q = await ContactQualityPrefs.get(_peerFromSession(sessionId));
    if (q != null) controller.applyContactDefaults(q.audio, q.video);
    while (mounted) {
      final r = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            controller: controller,
            contactName: name,
            photoUrl: photo,
            isOutgoing: outgoing,
            sessionId: sessionId,
            videoEnabled: video,
            resume: resume,
            hint: hint,
          ),
        ),
      );
      if (r != 'minimize') break;
      final back = await ActiveCall.minimize(
        controller,
        name: name,
        photo: photo,
        video: video,
      );
      if (!back) break;
      resume = true;
    }
  }

  /// A chat / friend request / missed call notification was tapped.
  void _handleOpenTap([Map<String, dynamic>? m]) {
    final p = m ?? CallNotification.pendingOpen;
    CallNotification.pendingOpen = null;
    if (p == null || !mounted) return;
    final kind = p['k']?.toString();
    final uid = p['u']?.toString() ?? '';
    if (kind == 'group_call') {
      _openLiveGroup(p['g']?.toString() ?? '');
      return;
    }
    if (kind == 'group_chat') {
      _openGroupChat(p['g']?.toString() ?? '');
      return;
    }
    if ((p['action'] == 'call' || p['action'] == 'call_now') && uid.isNotEmpty) {
      final c = widget.contactController.contacts.value
              .where((x) => x.uid == uid)
              .firstOrNull ??
          ContactModel(
            uid: uid,
            displayName: p['n']?.toString() ?? _nameFor(uid),
            addedAt: DateTime.now(),
          );
      _callContact(c, video: false);
      return;
    }
    if (kind == 'chat' && uid.isNotEmpty) {
      _openChatFor(uid);
    } else if (kind == 'friend_request') {
      _openAddContact();
    } else {
      _openRequests();
    }
  }

  Future<void> _openGroupChat(String gid) async {
    if (gid.isEmpty || !mounted) return;
    final gc = GroupController(widget.myUid);
    await gc.refresh();
    if (!mounted) {
      gc.dispose();
      return;
    }
    if (!gc.groups.value.any((x) => x.id == gid)) {
      gc.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That group is not available anymore.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          groupController: gc,
          groupId: gid,
          contactController: widget.contactController,
          myUid: widget.myUid,
        ),
      ),
    );
    gc.dispose();
  }

  void _openRequests() {
    _loadMissed().then((_) =>
        Future.delayed(const Duration(seconds: 2), _markMissedSeen));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          unread: _unread,
          preview: _preview,
          nameFor: _nameFor,
          onOpenChat: _openChatFor,
          onOpenAdd: _openAddContact,
          missed: _missed,
          contactController: widget.contactController,
        ),
      ),
    );
  }

void _openInbox() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChatInboxScreen(
              contactController: widget.contactController,
              myUid: widget.myUid,
            ),
          ),
        )
        .then((_) => _loadUnread());
  }

  void _openChatFor(String uid) {
    final c = widget.contactController.contacts.value
        .where((x) => x.uid == uid)
        .firstOrNull;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              contactName: c?.displayName ?? _nameFor(uid),
              contactUid: uid,
              myUid: widget.myUid,
              photoUrl: widget.contactController.photos.value[uid],
            ),
          ),
        )
        .then((_) => _loadUnread());
  }

  void _openAddContact() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AddContactScreen(contactController: widget.contactController),
      ),
    );
  }

  void _openGroups() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupsScreen(
          contactController: widget.contactController,
          myUid: widget.myUid,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _copyMyId() {
    Clipboard.setData(ClipboardData(text: widget.myUid));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID copied')),
    );
  }

  void _shareMyId() {
    Clipboard.setData(ClipboardData(text: widget.myUid));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ID copied to clipboard. (Share sheet requires share_plus package)',
        ),
      ),
    );
  }

  void _openGroupDetail(GroupModel g) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          groupController: _groupController,
          groupId: g.id,
          contactController: widget.contactController,
          myUid: widget.myUid,
        ),
      ),
    );
  }

  List<_ContactOrGroupItem> get _allItems => [
        for (final c in widget.contactController.contacts.value)
          _ContactOrGroupItem.contact(c),
        for (final g in _groupController.groups.value)
          _ContactOrGroupItem.group(g),
      ];

  void _startInlineChat(_ContactOrGroupItem item) {
    _disposeInlineChat();
    if (item.isGroup) {
      _inlineGroupChatService =
          GroupChatService(groupId: item.id, myUid: widget.myUid);
      _inlineGroupChatService!.start();
    } else {
      _inlineChatService =
          ChatService(myUid: widget.myUid, peerUid: item.id);
      _inlineChatService!.start();
      _inlineVoiceService =
          VoiceService(myUid: widget.myUid, peerUid: item.id);
      _inlineVoiceService!.start();
    }
  }

  void _disposeInlineChat() {
    _inlineChatService?.dispose();
    _inlineChatService = null;
    _inlineGroupChatService?.dispose();
    _inlineGroupChatService = null;
    _inlineVoiceService?.dispose();
    _inlineVoiceService = null;
  }

  Future<void> _onTapTile(int index, _ContactOrGroupItem item) async {
    final key = item.isGroup ? 'g:${item.id}' : 'u:${item.id}';
    if (ChatPrefs.locked.value.contains(key)) {
      final ok = await askChatPin(context);
      if (!ok || !mounted) return;
    }
    setState(() {
      _selectedTileIndex = index;
      _selectedItem = item;
    });
    // Start animation first (250-300ms easeOutCubic); load or decrypt messages right after so animation never stutters
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted && _selectedItem == item) {
        _startInlineChat(item);
      }
    });
  }

  Future<void> _switchExpandedTile(int index, _ContactOrGroupItem item) async {
    final key = item.isGroup ? 'g:${item.id}' : 'u:${item.id}';
    if (ChatPrefs.locked.value.contains(key)) {
      final ok = await askChatPin(context);
      if (!ok || !mounted) return;
    }
    setState(() {
      _selectedTileIndex = index;
      _selectedItem = item;
    });
    // Start animation first; load or decrypt messages right after
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted && _selectedItem == item) {
        _startInlineChat(item);
      }
    });
  }

  void _closeExpandedTile() {
    _disposeInlineChat();
    setState(() {
      _selectedTileIndex = null;
      _selectedItem = null;
      _inlineTextCtrl.clear();
      _inlineHasText = false;
    });
  }

  void _openFullChat(_ContactOrGroupItem item) {
    if (item.isGroup) {
      _openGroupChat(item.id);
    } else {
      _openChatFor(item.id);
    }
  }

  Future<void> _sendInlineText() async {
    final text = _inlineTextCtrl.text.trim();
    if (text.isEmpty || _selectedItem == null) return;
    _inlineTextCtrl.clear();
    setState(() => _inlineHasText = false);
    if (_selectedItem!.isGroup) {
      await _inlineGroupChatService?.send(text);
    } else {
      await _inlineChatService?.sendText(text);
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _attachFileInline() async {
    if (_inlineChatService == null) return;
    final x = await openFile();
    if (x == null) return;
    try {
      await _inlineChatService!.sendFile(File(x.path), x.name);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send the file. Try again.')),
        );
      }
    }
  }

  Future<void> _startInlineVoice() async {
    if (_inlineVoiceService == null || _recordingVoice) return;
    bool started = false;
    try {
      started = await _inlineVoiceService!.startRecording();
    } catch (_) {
      started = false;
    }
    if (!started || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is needed.')),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _recordingVoice = true;
      _voiceSecs = 0;
    });
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _voiceSecs++);
      if (_voiceSecs >= VoiceService.maxSeconds) _finishInlineVoice(true);
    });
  }

  Future<void> _finishInlineVoice(bool send) async {
    if (!_recordingVoice || _inlineVoiceService == null) return;
    _voiceTimer?.cancel();
    setState(() => _recordingVoice = false);
    if (!send) {
      await _inlineVoiceService!.cancelRecording();
      return;
    }
    dynamic r;
    try {
      r = await _inlineVoiceService!.stopRecording();
    } catch (_) {
      r = null;
    }
    if (r == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Too short. Record for at least a second.')),
        );
      }
      return;
    }
    try {
      await _inlineVoiceService!.send(r.file, r.seconds);
      HapticFeedback.lightImpact();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice message not sent. Try again.')),
        );
      }
    }
  }

  String _formatPreview(_ContactOrGroupItem item) {
    if (_callTileStatus.containsKey(item.id)) {
      return _callTileStatus[item.id]!;
    }
    final key = item.isGroup ? 'g:${item.id}' : 'u:${item.id}';
    if (ChatPrefs.locked.value.contains(key)) {
      return 'Locked chat';
    }
    final p = _preview.value[item.id];
    if (p != null && p.isNotEmpty) {
      return p;
    }
    return item.isGroup
        ? '${item.group?.members.length ?? 0} members'
        : item.id;
  }

  Widget _buildMyIdCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.tileFill(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.tileBorder(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'My ID',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                widget.myUid,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMain(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.copy, color: AppColors.accent(context), size: 20),
            tooltip: 'Copy ID',
            onPressed: _copyMyId,
          ),
          IconButton(
            icon: Icon(Icons.share, color: AppColors.accent(context), size: 20),
            tooltip: 'Share ID',
            onPressed: _shareMyId,
          ),
        ],
      ),
    );
  }

  Widget _buildTile(int index, _ContactOrGroupItem item) {
    if (item.isGroup) {
      return _buildGroupTile(index, item.group!);
    }
    return _buildContactTile(index, item.contact!);
  }

  Widget _buildContactTile(int index, ContactModel contact) {
    final unreadCount = _unread.value[contact.uid] ?? 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tileFill(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.tileBorder(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 220) {
            _openFullChat(_ContactOrGroupItem.contact(contact));
          }
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: () => _openContact(contact),
              child: ValueListenableBuilder<Map<String, String>>(
                valueListenable: widget.contactController.photos,
                builder: (context, photos, _) {
                  if (!photos.containsKey(contact.uid)) {
                    widget.contactController.fetchPhoto(contact.uid);
                  }
                  return UserAvatar(
                    name: contact.displayName,
                    photoUrl: photos[contact.uid],
                  );
                },
              ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: ValueListenableBuilder<Set<String>>(
                valueListenable: _presence.online,
                builder: (context, on, _) => on.contains(contact.uid)
                    ? Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: Colors.greenAccent[700],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
        title: Text(
          contact.displayName,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textMain(context),
            fontWeight: FontWeight.w600,
            fontSize: 15.5,
          ),
        ),
        subtitle: Text(
          _formatPreview(_ContactOrGroupItem.contact(contact)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13.5,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unreadCount > 0)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent(context),
                  shape: BoxShape.circle,
                ),
              ),
            IconButton(
              icon: Icon(Icons.call, color: AppColors.accent(context), size: 22),
              tooltip: 'Voice call',
              onPressed: () => _callContact(contact, video: false),
            ),
            IconButton(
              icon: Icon(Icons.videocam,
                  color: AppColors.accent(context), size: 22),
              tooltip: 'Video call',
              onPressed: () => _callContact(contact, video: true),
            ),
          ],
        ),
        onTap: () => _onTapTile(index, _ContactOrGroupItem.contact(contact)),
      ),
    ),
  );
}

  Widget _buildGroupTile(int index, GroupModel group) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tileFill(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.tileBorder(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 220) {
            _openFullChat(_ContactOrGroupItem.group(group));
          }
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: GestureDetector(
          onTap: () => _openGroupDetail(group),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Color(group.color),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(group.emoji, style: const TextStyle(fontSize: 22)),
          ),
        ),
        title: Text(
          group.name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textMain(context),
            fontWeight: FontWeight.w600,
            fontSize: 15.5,
          ),
        ),
        subtitle: Text(
          _formatPreview(_ContactOrGroupItem.group(group)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13.5,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.call, color: AppColors.accent(context), size: 22),
              tooltip: 'Group call',
              onPressed: () => _openGroupCall(
                group.id,
                group.name,
                group.emoji,
                group.color,
                group.mode,
                false,
              ),
            ),
          ],
        ),
        onTap: () => _onTapTile(index, _ContactOrGroupItem.group(group)),
      ),
    ),
  );
}

  Widget _buildCollapsedNeighborTile(int index, _ContactOrGroupItem item) {
    final isGroup = item.isGroup;
    final unreadCount = !isGroup ? (_unread.value[item.id] ?? 0) : 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tileFill(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.tileBorder(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 220) {
            _openFullChat(item);
          }
        },
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: isGroup
            ? GestureDetector(
                onTap: () => _openGroupDetail(item.group!),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(item.group!.color),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(item.group!.emoji,
                      style: const TextStyle(fontSize: 22)),
                ),
              )
            : GestureDetector(
                onTap: () => _openContact(item.contact!),
                child: UserAvatar(
                  name: item.name,
                  photoUrl: widget.contactController.photos.value[item.id],
                ),
              ),
        title: Text(
          item.name,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textMain(context),
            fontWeight: FontWeight.w600,
            fontSize: 15.5,
          ),
        ),
        subtitle: Text(
          _formatPreview(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13.5,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unreadCount > 0)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent(context),
                  shape: BoxShape.circle,
                ),
              ),
            if (!isGroup) ...[
              IconButton(
                icon:
                    Icon(Icons.call, color: AppColors.accent(context), size: 22),
                onPressed: () => _callContact(item.contact!, video: false),
              ),
              IconButton(
                icon: Icon(Icons.videocam,
                    color: AppColors.accent(context), size: 22),
                onPressed: () => _callContact(item.contact!, video: true),
              ),
            ] else ...[
              IconButton(
                icon:
                    Icon(Icons.call, color: AppColors.accent(context), size: 22),
                onPressed: () => _openGroupCall(
                  item.group!.id,
                  item.group!.name,
                  item.group!.emoji,
                  item.group!.color,
                  item.group!.mode,
                  false,
                ),
              ),
            ],
          ],
        ),
        onTap: () => _switchExpandedTile(index, item),
      ),
    ),
  );
}

  Widget _buildExpandedTile(int index, _ContactOrGroupItem item) {
    final isGroup = item.isGroup;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.openChatTile(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.tileBorder(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity!.abs() > 220) {
                _openFullChat(item);
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  isGroup
                      ? GestureDetector(
                          onTap: () => _openGroupDetail(item.group!),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Color(item.group!.color),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(item.group!.emoji,
                                style: const TextStyle(fontSize: 18)),
                          ),
                        )
                      : GestureDetector(
                          onTap: () => _openContact(item.contact!),
                          child: ValueListenableBuilder<Set<String>>(
                            valueListenable: _presence.online,
                            builder: (context, onSet, _) {
                              final on = onSet.contains(item.id);
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  UserAvatar(
                                    name: item.name,
                                    photoUrl: widget
                                        .contactController.photos.value[item.id],
                                    radius: 19,
                                  ),
                                  if (on)
                                    Positioned(
                                      right: -1,
                                      bottom: -1,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent[700],
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.openChatTile(context),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMain(context),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (!isGroup)
                          ValueListenableBuilder<Set<String>>(
                            valueListenable: _presence.online,
                            builder: (context, onSet, _) {
                              if (!onSet.contains(item.id)) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                'online',
                                style: TextStyle(
                                  color: AppColors.accent(context),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                if (!isGroup) ...[
                  IconButton(
                    icon: Icon(Icons.call,
                        color: AppColors.accent(context), size: 20),
                    tooltip: 'Voice call',
                    onPressed: () => _callContact(item.contact!, video: false),
                  ),
                  IconButton(
                    icon: Icon(Icons.videocam,
                        color: AppColors.accent(context), size: 20),
                    tooltip: 'Video call',
                    onPressed: () => _callContact(item.contact!, video: true),
                  ),
                ] else ...[
                  IconButton(
                    icon: Icon(Icons.call,
                        color: AppColors.accent(context), size: 20),
                    tooltip: 'Group call',
                    onPressed: () => _openGroupCall(
                      item.group!.id,
                      item.group!.name,
                      item.group!.emoji,
                      item.group!.color,
                      item.group!.mode,
                      false,
                    ),
                  ),
                ],
                IconButton(
                  icon: Icon(Icons.open_in_full,
                      size: 19, color: AppColors.accent(context)),
                  tooltip: 'Open full chat',
                  onPressed: () => _openFullChat(item),
                ),
                IconButton(
                  icon: Icon(Icons.close,
                      size: 20, color: AppColors.textSecondary(context)),
                  tooltip: 'Close',
                  onPressed: _closeExpandedTile,
                ),
              ],
            ),
          ),
        ),
        Divider(color: AppColors.divider(context), height: 1),
          // Messages list
          Expanded(
            child: isGroup
                ? _buildInlineGroupMessages()
                : _buildInlineMessages(),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineMessages() {
    if (_inlineChatService == null) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accent(context)),
      );
    }
    return AnimatedBuilder(
      animation: Listenable.merge([
        _inlineChatService!.messages,
        if (_inlineVoiceService != null) _inlineVoiceService!.messages,
      ]),
      builder: (context, _) {
        final chatMsgs = _inlineChatService!.messages.value;
        final voiceMsgs = _inlineVoiceService?.messages.value ?? [];

        final items = <_InlineItem>[
          for (final m in chatMsgs) _InlineItem(at: m.createdAt, chat: m),
          for (final v in voiceMsgs) _InlineItem(at: v.createdAt, voice: v),
        ]..sort((a, b) => a.at.compareTo(b.at));

        if (items.isEmpty) {
          return Center(
            child: Text(
              'No messages yet. Say hi!',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final it = items[i];
            return _buildInlineBubble(it);
          },
        );
      },
    );
  }

  Widget _buildInlineBubble(_InlineItem it) {
    if (it.voice != null) {
      final v = it.voice!;
      return VoiceBubble(
        m: v,
        mine: v.fromUid == widget.myUid,
        player: _inlineVoicePlayer,
        svc: _inlineVoiceService!,
        onError: (msg) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        },
        onLongPress: () {},
      );
    }
    final m = it.chat!;
    final mine = m.fromUid == widget.myUid;
    final fg = mine ? Colors.white : AppColors.textMain(context);

    Widget content;
    if (m.kind == 'file' && isImageName(m.fileName)) {
      content = PhotoBubble(m: m, svc: _inlineChatService!);
    } else if (m.kind == 'file') {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, size: 20, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              m.fileName ?? 'File',
              style: TextStyle(color: fg),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else {
      content = Text(
        m.body ?? '',
        style: TextStyle(color: fg, fontSize: 14.5),
      );
    }

    final hm = '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';
    final bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.editedAt != null)
              Text('edited  ',
                  style: TextStyle(color: fg.withOpacity(0.7), fontSize: 11)),
            Text(hm,
                style: TextStyle(color: fg.withOpacity(0.7), fontSize: 11)),
            if (mine) ...[
              const SizedBox(width: 6),
              Icon(m.status > 0 ? Icons.done_all : Icons.done,
                  size: 14,
                  color: Colors.white
                      .withOpacity(m.status == 2 ? 1 : 0.85)),
              const SizedBox(width: 2),
              Text(
                m.status == 2
                    ? 'Read'
                    : (m.status == 1 ? 'Delivered' : 'Sent'),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ],
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color:
              mine ? AppColors.myBubble(context) : AppColors.tileFill(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.tileBorder(context),
            width: 0.5,
          ),
        ),
        child: bubbleContent,
      ),
    );
  }

  Widget _buildInlineGroupMessages() {
    if (_inlineGroupChatService == null) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accent(context)),
      );
    }
    return ValueListenableBuilder<List<GroupMessage>>(
      valueListenable: _inlineGroupChatService!.messages,
      builder: (context, msgs, _) {
        if (msgs.isEmpty) {
          return Center(
            child: Text(
              'No messages yet in this group.',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: msgs.length,
          itemBuilder: (context, i) {
            final m = msgs[i];
            final mine = m.fromUid == widget.myUid;
            final senderName = _groupController.nameOf(m.fromUid);
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                decoration: BoxDecoration(
                  color: mine
                      ? AppColors.myBubble(context)
                      : AppColors.tileFill(context),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: AppColors.tileBorder(context), width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!mine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          senderName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent(context),
                          ),
                        ),
                      ),
                    Text(
                      m.body,
                      style: TextStyle(
                        color: mine ? Colors.white : AppColors.textMain(context),
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showRecentsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.55,
              color: AppColors.bottomBar(context),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.tileBorder(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.history,
                            color: AppColors.accent(context), size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Recent calls',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMain(context),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close,
                              color: AppColors.textSecondary(context)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: AppColors.tileBorder(context), height: 1),
                  Expanded(
                    child: ValueListenableBuilder<List<CallLogEntry>>(
                      valueListenable: _log.entries,
                      builder: (context, entries, _) {
                        if (entries.isEmpty) {
                          return Center(
                            child: Text(
                              'No recent calls',
                              style: TextStyle(
                                  color: AppColors.textSecondary(context)),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          separatorBuilder: (_, __) => Divider(
                            color:
                                AppColors.tileBorder(context).withOpacity(0.3),
                            height: 1,
                          ),
                          itemCount: entries.length,
                          itemBuilder: (context, i) {
                            final e = entries[i];
                            return ListTile(
                              leading: UserAvatar(
                                name: _nameFor(e.uid),
                                photoUrl: widget
                                    .contactController.photos.value[e.uid],
                                radius: 20,
                              ),
                              title: Text(
                                _nameFor(e.uid),
                                style: TextStyle(
                                  color: AppColors.textMain(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${_when(e.time)} · ${e.video ? 'Video' : 'Voice'} · ${_callResultLabel(e)}',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 12.5,
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  e.video ? Icons.videocam : Icons.call,
                                  color: AppColors.accent(context),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _callBack(e);
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _callResultLabel(CallLogEntry e) {
    switch (e.result) {
      case CallResult.answered:
        final m = e.seconds ~/ 60;
        final s = e.seconds % 60;
        return '$m:${s.toString().padLeft(2, '0')}';
      case CallResult.missed:
        return 'Missed';
      case CallResult.declined:
        return 'Declined';
      case CallResult.cancelled:
        return e.outgoing ? 'No answer' : 'Cancelled';
    }
  }

  String _when(DateTime t) {
    final now = DateTime.now();
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final today =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return today ? 'Today $hm' : '${t.day}/${t.month} $hm';
  }

  Widget _buildRecentsPill() {
    return InkWell(
      key: const ValueKey('recents_pill'),
      onTap: _showRecentsSheet,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.tileFill(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.tileBorder(context), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.history, color: AppColors.accent(context), size: 20),
            const SizedBox(width: 10),
            Text(
              'Recents',
              style: TextStyle(
                color: AppColors.textMain(context),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            Icon(Icons.keyboard_arrow_up, color: AppColors.accent(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingPill() {
    return Container(
      key: const ValueKey('typing_pill'),
      decoration: BoxDecoration(
        color: AppColors.tileFill(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.tileBorder(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file,
                color: AppColors.accent(context), size: 20),
            tooltip: 'Attach file',
            onPressed: _attachFileInline,
          ),
          Expanded(
            child: TextField(
              controller: _inlineTextCtrl,
              style: TextStyle(
                  color: AppColors.textMain(context), fontSize: 14.5),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(
                    color: AppColors.textSecondary(context), fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: (_) => _sendInlineText(),
            ),
          ),
          if (_recordingVoice)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${_voiceSecs}s',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCircularActionButton(bool hasOpen) {
    if (hasOpen) {
      final showSend = _inlineHasText;
      return GestureDetector(
        onTap: showSend
            ? _sendInlineText
            : () {
                if (_recordingVoice) {
                  _finishInlineVoice(true);
                } else {
                  _startInlineVoice();
                }
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _recordingVoice
                ? Colors.redAccent
                : AppColors.accent(context),
            boxShadow: [
              BoxShadow(
                color: (_recordingVoice
                        ? Colors.redAccent
                        : AppColors.accent(context))
                    .withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            showSend
                ? Icons.send
                : (_recordingVoice ? Icons.stop : Icons.mic),
            color: AppColors.c051F20,
            size: 22,
          ),
        ),
      );
    }

    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: _unread,
      builder: (context, u, _) {
        final n = u.values.fold<int>(0, (a, b) => a + b);
        return GestureDetector(
          onTap: _openInbox,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent(context),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent(context).withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Badge(
              isLabelVisible: n > 0,
              label: Text('$n'),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.c051F20,
                size: 24,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final hasOpen = _selectedTileIndex != null;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          color: AppColors.bottomBar(context),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: hasOpen
                        ? _buildTypingPill()
                        : _buildRecentsPill(),
                  ),
                ),
                const SizedBox(width: 10),
                _buildCircularActionButton(hasOpen),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cover) return const Scaffold(backgroundColor: Color(0xFF042F2E));
    final hasOpen = _selectedTileIndex != null;
    final bg = AppColors.screenBackground(context);

    return PopScope(
      canPop: !hasOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && hasOpen) {
          _closeExpandedTile();
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  tooltip: 'Profile',
                  onPressed: _openProfile,
                  icon: UserAvatar(
                    name: _me?.name ?? '?',
                    photoUrl: _me?.photoUrl,
                    radius: 16,
                  ),
                ),
                title: Text(
                  'QualityTime',
                  style: TextStyle(
                    color: AppColors.textMain(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                actions: [
                  AnimatedBuilder(
                    animation: Listenable.merge(
                        [widget.contactController.incoming, _unread, _missed]),
                    builder: (context, _) {
                      final n = widget.contactController.incoming.value.length +
                          _unread.value.length +
                          _missed.value.where((m) => m['seen'] != true).length;
                      return IconButton(
                        tooltip: 'Notifications',
                        onPressed: _openRequests,
                        icon: Badge(
                          isLabelVisible: n > 0,
                          label: Text('$n'),
                          child: Icon(Icons.notifications_none,
                              color: AppColors.textMain(context)),
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<List<Map<String, String>>>(
                    valueListenable: widget.contactController.incoming,
                    builder: (context, list, _) => IconButton(
                      tooltip: 'Add friend',
                      onPressed: _openAddContact,
                      icon: Badge(
                        isLabelVisible: list.isNotEmpty,
                        label: Text('${list.length}'),
                        child: Icon(Icons.person_add,
                            color: AppColors.textMain(context)),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Groups',
                    icon: AnimatedBuilder(
                      animation: Listenable.merge(
                          [GroupStatus.live, GroupStatus.unread]),
                      builder: (context, _) {
                        final liveNow = GroupStatus.live.value.isNotEmpty;
                        final n = GroupStatus.unread.value.values
                            .fold<int>(0, (a, b) => a + b);
                        return Badge(
                          isLabelVisible: liveNow || n > 0,
                          backgroundColor: Colors.red,
                          smallSize: 10,
                          label: liveNow ? null : Text('$n'),
                          child: Icon(Icons.groups_outlined,
                              color: AppColors.textMain(context)),
                        );
                      },
                    ),
                    onPressed: _openGroups,
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    icon: Icon(Icons.settings_outlined,
                        color: AppColors.textMain(context)),
                    onPressed: _openSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge(
              [AppSettings.wallpaper, AppSettings.wallpaperBlur]),
          builder: (context, child) {
            final wp = AppSettings.wallpaper.value;
            Widget bgWidget;
            if (wp == null) {
              bgWidget = ColoredBox(color: bg);
            } else {
              final blurOn = AppSettings.wallpaperBlur.value;
              final img = Image.file(
                File(wp),
                fit: BoxFit.cover,
                cacheWidth: blurOn ? 48 : 1080,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              );
              bgWidget = Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(child: img),
                  ColoredBox(color: bg.withOpacity(0.5)),
                ],
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [bgWidget, child!],
            );
          },
          child: Stack(
            children: [
              SafeArea(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    widget.contactController.contacts,
                    _groupController.groups,
                    _unread,
                    _preview,
                  ]),
                  builder: (context, _) {
                    final allItems = _allItems;
                    return Column(
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: NetStatus.online,
                          builder: (context, on, _) => on
                              ? const SizedBox.shrink()
                              : Container(
                                  width: double.infinity,
                                  color: Colors.orange.shade800,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: const Text(
                                    "You're offline. Showing saved data.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 12.5),
                                  ),
                                ),
                        ),
                        if (!hasOpen) _buildMyIdCard(),
                        Expanded(
                          child: allItems.isEmpty
                              ? Center(
                                  child: Text(
                                    'No contacts yet. Tap + to add one.',
                                    style: TextStyle(
                                        color: AppColors.textSecondary(context)),
                                  ),
                                )
                              : AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 280),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeOutCubic,
                                  child: !hasOpen
                                      ? ListView.builder(
                                          key: const ValueKey('contacts_list_view'),
                                          physics: const BouncingScrollPhysics(
                                            parent: AlwaysScrollableScrollPhysics(),
                                          ),
                                          padding: const EdgeInsets.only(
                                              top: 4, bottom: 96),
                                          itemCount: allItems.length,
                                          itemBuilder: (context, index) =>
                                              _buildTile(index, allItems[index]),
                                        )
                                      : _buildExpanded3TilesView(allItems),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded3TilesView(List<_ContactOrGroupItem> allItems) {
    final sel = _selectedTileIndex ?? 0;
    final N = allItems.length;
    List<int> visibleIndices;
    if (N <= 3) {
      visibleIndices = List.generate(N, (i) => i);
    } else if (sel == 0) {
      visibleIndices = [0, 1, 2];
    } else if (sel == N - 1) {
      visibleIndices = [N - 3, N - 2, N - 1];
    } else {
      visibleIndices = [sel - 1, sel, sel + 1];
    }

    return Padding(
      key: ValueKey('expanded_3tiles_$sel'),
      padding: const EdgeInsets.only(bottom: 84),
      child: Column(
        children: [
          for (final i in visibleIndices)
            if (i == sel)
              Expanded(
                child: _buildExpandedTile(i, allItems[i]),
              )
            else
              _buildCollapsedNeighborTile(i, allItems[i]),
        ],
      ),
    );
  }
}