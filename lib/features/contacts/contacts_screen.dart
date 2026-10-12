import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'friend_requests_screen.dart';
import 'dart:io' show File;
import '../../utils/settings/app_settings.dart';
import 'dart:ui' show ImageFilter;
import '../../utils/glass.dart';
import '../settings/settings_screen.dart';
import '../groups/groups_screen.dart';
import '../groups/group_controller.dart';
import '../groups/group_call_screen.dart';
import '../../utils/settings/contact_quality_prefs.dart';

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

  // Unread chat messages per friend (waiting in the cloud).
  final _unread = ValueNotifier<Map<String, int>>({});
  RealtimeChannel? _chatCh;

  Future<void> _loadUnread() async {
    try {
      final rows = await Supabase.instance.client
          .from('chat_messages')
          .select('from_uid')
          .eq('to_uid', widget.myUid);
      final m = <String, int>{};
      for (final r in rows as List) {
        final u = r['from_uid'] as String;
        m[u] = (m[u] ?? 0) + 1;
      }
      if (mounted) _unread.value = m;
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
    _initCover();
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
    widget.contactController
        .syncWithCloud()
        .then((_) => widget.contactController.refreshProfiles())
        .then((_) => widget.contactController.startFriends());
    NetStatus.online.addListener(_onNet);
    _loadMe();
    _presence = PresenceService(widget.myUid)..start();
    _loadUnread();
    _chatCh = Supabase.instance.client
        .channel('chat_unread')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => _loadUnread(),
        )
        .subscribe();
    widget.contactController.contacts.addListener(_watchContacts);
    _watchContacts();
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
    _presence.dispose();
    _chatCh?.unsubscribe();
    _unread.dispose();
    _ringSub?.cancel();
    _cancelSub?.cancel();
    _gringSub?.cancel();
    _acceptSub?.cancel();
    _declineSub?.cancel();
    _log.dispose();
    _tones.dispose();
    _service.dispose();
    super.dispose();
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
    final err = await widget.contactController.sendFriendRequest(uid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Friend request sent')),
    );
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
        _service.sendBusy(toUid: call.fromUid, sessionId: call.sessionId);
        if (!kIsWeb) CallKitService.instance.endCall(call.sessionId);
      }
      return;
    }
    _busy = true;
    if (!await widget.contactController.isFriend(call.fromUid)) {
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
    if (_busy || !mounted || g.groupId.isEmpty) return;
    final sid = 'group_${g.groupId}';
    _busy = true;
    _incomingSession = sid;
    if (!kIsWeb) CallNotification.cancel();
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
    if (call.sessionId.startsWith('group_')) return;
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
    if (!NetStatus.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're offline. Can't call right now.")),
      );
      return;
    }
    _busy = true;
    if (!await widget.contactController.isFriend(contact.uid)) {
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

    final declineSub = _service.onDecline.listen((s) async {
      if (s != sessionId || !mounted) return;
      controller.endLabel = 'Call declined';
      wasDeclined = true;
      _tones.playBusy();
      await controller.endCall(notifyPeer: false);
    });

    final busySub = _service.onBusy.listen((s) async {
      if (s != sessionId || !mounted) return;
      final p = controller.phase.value;
      if (p == CallPhase.active || p == CallPhase.ended) return;
      controller.endLabel = 'On another call';
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
    offlineTimer = Timer(const Duration(seconds: 8), () async {
      if (ringbackOn || controller.phase.value != CallPhase.connecting) {
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

  void _openRequests() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FriendRequestsScreen(
          contactController: widget.contactController,
        ),
      ),
    );
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

  Widget _buildMyIdCard() {
    final tile = ListTile(
      title: const Text('My ID'),
      subtitle: SelectableText(widget.myUid),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        tooltip: 'Copy ID',
        onPressed: _copyMyId,
      ),
    );
    return ValueListenableBuilder<String?>(
      valueListenable: AppSettings.wallpaper,
      builder: (context, wp, _) {
        if (wp == null) {
          return Card(margin: const EdgeInsets.all(12), child: tile);
        }
        final s = Theme.of(context).colorScheme;
        return Glass(
          margin: const EdgeInsets.all(12),
          blur: 10,
          tint: s.surface,
          opacity: 0.45,
          borderRadius: BorderRadius.circular(18),
          child: tile,
        );
      },
    );
  }

  Widget _buildContactTile(ContactModel contact) {
    final tile = _contactTile(contact);
    return ValueListenableBuilder<String?>(
      valueListenable: AppSettings.wallpaper,
      builder: (context, wp, _) {
        if (wp == null) return tile;
        final s = Theme.of(context).colorScheme;
        return Glass(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          blur: 10,
          tint: s.surface,
          opacity: 0.45,
          borderRadius: BorderRadius.circular(18),
          child: tile,
        );
      },
    );
  }

  Widget _contactTile(ContactModel contact) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          ValueListenableBuilder<Map<String, String>>(
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
      title: ValueListenableBuilder<Map<String, int>>(
        valueListenable: _unread,
        builder: (context, u, _) {
          final n = u[contact.uid] ?? 0;
          return Row(
            children: [
              Flexible(
                child: Text(
                  contact.displayName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (n > 0) ...[
                const SizedBox(width: 8),
                Badge(label: Text('$n')),
              ],
            ],
          );
        },
      ),
      subtitle: Text(contact.uid),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => _callContact(contact, video: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _callContact(contact, video: true),
          ),
        ],
      ),
      onTap: () => _openContact(contact),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cover) return const Scaffold(backgroundColor: Color(0xFF042F2E));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Profile',
          onPressed: _openProfile,
          icon: UserAvatar(
            name: _me?.name ?? '?',
            photoUrl: _me?.photoUrl,
            radius: 15,
          ),
        ),
        title: const Text('Contacts'),
        actions: [
          ValueListenableBuilder<List<Map<String, String>>>(
            valueListenable: widget.contactController.incoming,
            builder: (context, list, _) => IconButton(
              tooltip: 'Friend requests',
              onPressed: _openRequests,
              icon: Badge(
                isLabelVisible: list.isNotEmpty,
                label: Text('${list.length}'),
                child: const Icon(Icons.notifications_none),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add friend',
            icon: const Icon(Icons.person_add),
            onPressed: _openAddContact,
          ),
          IconButton(
            tooltip: 'Groups',
            icon: const Icon(Icons.groups_outlined),
            onPressed: _openGroups,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(
            [AppSettings.wallpaper, AppSettings.wallpaperBlur]),
        builder: (context, child) {
          final wp = AppSettings.wallpaper.value;
          final scheme = Theme.of(context).colorScheme;
          Widget bg;
          if (wp == null) {
            bg = DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primaryContainer.withOpacity(0.6),
                    scheme.surface,
                  ],
                ),
              ),
            );
          } else {
            final img = Image.file(File(wp), fit: BoxFit.cover);
            bg = Stack(
              fit: StackFit.expand,
              children: [
                AppSettings.wallpaperBlur.value
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: img,
                      )
                    : img,
                ColoredBox(color: scheme.surface.withOpacity(0.5)),
              ],
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [bg, child!],
          );
        },
        child: Stack(
        children: [
          Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: NetStatus.online,
            builder: (context, on, _) => on
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    color: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: const Text(
                      "You're offline. Showing saved data.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12.5),
                    ),
                  ),
          ),
          _buildMyIdCard(),
          Expanded(
            child: ValueListenableBuilder<List<ContactModel>>(
              valueListenable: widget.contactController.contacts,
              builder: (context, contacts, _) {
                if (contacts.isEmpty) {
                  return const Center(
                    child: Text('No contacts yet. Tap + to add one.'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: contacts.length,
                  itemBuilder: (context, index) =>
                      _buildContactTile(contacts[index]),
                );
              },
            ),
          ),
        ],
      ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: CallLogPanel(
              log: _log,
              refresh: widget.contactController.contacts,
              photos: widget.contactController.photos,
              fetchPhoto: widget.contactController.fetchPhoto,
              nameFor: _nameFor,
              isSaved: _isSaved,
              onAdd: _addFromLog,
              onCallBack: _callBack,
            ),
          ),
        ],
      ),
      ),
    );
  }
}