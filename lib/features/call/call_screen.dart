import 'dart:ui' show ImageFilter;
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/user_avatar.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_controller.dart';
import 'animated_call_button.dart';
import 'quality_sheet.dart';
import '../../core/webrtc/quality_choice.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../utils/blurred_photo.dart';
import 'dart:io' show File;
import '../../utils/settings/app_settings.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import '../../utils/lock_screen.dart';
import '../../utils/glass.dart';
import '../contacts/contact_controller.dart';
import '../groups/group_controller.dart';
import '../groups/groups_screen.dart';
import '../groups/group_call_screen.dart';
import '../../core/signaling/group_ring_service.dart';
import 'package:audioplayers/audioplayers.dart' as ap;

class CallScreen extends StatefulWidget {
  final CallController controller;
  final String contactName;
  final bool isOutgoing;
  final String sessionId;
  final bool videoEnabled;
  final String? photoUrl;
  final bool resume;
  final ValueListenable<String?>? hint;

  const CallScreen({
    super.key,
    required this.controller,
    required this.contactName,
    required this.isOutgoing,
    required this.sessionId,
    this.videoEnabled = true,
    this.photoUrl,
    this.resume = false,
    this.hint,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final _holdPlayer = ap.AudioPlayer();
  bool _speakerOn = false;
  bool _pip = false;
  bool _frontCamera = true;
  String? _roomId;
  String _roomName = 'Call';
  String _roomEmoji = '📞';
  int _roomColor = 0xFF0D9488;
  String _roomMode = 'friends';
  bool _roomVideo = false;
  GroupController? _roomGc;
  final _noHint = ValueNotifier<String?>(null);
  static const _pipChannel = MethodChannel('qt/pip');

  @override
  void initState() {
    super.initState();
    LockScreen.hold();
    _pipChannel.setMethodCallHandler((c) async {
      if (!mounted) return;
      if (c.method == 'pip') {
        setState(() => _pip = c.arguments == true);
        if (c.arguments == true) _sendPipState();
      } else if (c.method == 'pipAction') {
        _pipAction(c.arguments?.toString() ?? '');
      }
    });
    widget.controller.phase.addListener(_syncPip);
    widget.controller.remoteOnHold.addListener(_syncHoldSound);
    widget.controller.groupInvite.addListener(_onGroupInvite);
    _loadTint();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onGroupInvite());
    widget.controller.videoActive.addListener(_syncPip);
    _syncPip();
    _init();
  }

  Future<void> _syncHoldSound() async {
    final on = widget.controller.remoteOnHold.value;
    try {
      if (on) {
        final id = AppSettings.holdTone.value;
        if (id == 'off') return;
        await _holdPlayer.setReleaseMode(ap.ReleaseMode.loop);
        await _holdPlayer.play(AppSettings.sourceFor(id), volume: 0.5);
      } else {
        await _holdPlayer.stop();
      }
    } catch (_) {}
  }

  void _sendPipState() {
    final c = widget.controller;
    _pipChannel.invokeMethod('pipState', {
      'mic': c.micEnabled,
      'cam': c.mediaManager.hasVideo && c.cameraEnabled,
    }).catchError((_) {});
  }

  Future<void> _pipAction(String a) async {
    await _pipActionOld(a);
    _sendPipState();
  }

  Future<void> _pipActionOld(String a) async {
    final c = widget.controller;
    if (a == 'mute') {
      c.toggleMic();
    } else if (a == 'video') {
      await c.toggleCamera();
    } else if (a == 'end') {
      await _endCall();
      return;
    }
    if (mounted) setState(() {});
  }

  /// PiP is allowed only while a video call is connected.
  void _syncPip() {
    final c = widget.controller;
    final on = c.phase.value == CallPhase.active && c.videoActive.value;
    _pipChannel.invokeMethod('setAuto', on).catchError((_) {});
  }

  Widget _pipView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: widget.controller.remoteCameraOn,
            builder: (context, on, _) => on
                ? const SizedBox.shrink()
                : Container(
                    color: const Color(0xFF042F2E),
                    child: Center(
                      child: UserAvatar(
                        name: widget.contactName,
                        photoUrl: widget.photoUrl,
                        radius: 36,
                      ),
                    ),
                  ),
          ),
          if (!widget.controller.micEnabled)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.mic_off, color: Colors.redAccent, size: 18),
            ),
        ],
      ),
    );
  }

  Future<void> _init() async {
    if (!widget.resume) widget.controller.peerName = widget.contactName;
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    widget.controller.remoteStream.addListener(_onRemoteStreamChanged);
    widget.controller.phase.addListener(_onPhaseChanged);
    widget.controller.videoActive.addListener(_onVideoActive);

    if (widget.resume) {
      _speakerOn = widget.controller.speakerOn;
      try {
        await Helper.setSpeakerphoneOn(_speakerOn);
      } catch (_) {}
      if (widget.controller.mediaManager.hasVideo) WakelockPlus.enable();
      if (!mounted) return;
      _localRenderer.srcObject = widget.controller.localStream;
      _remoteRenderer.srcObject = widget.controller.remoteStream.value;
      setState(() {});
      return;
    }

    if (widget.isOutgoing) {
      await widget.controller.startOutgoingCall(
        widget.sessionId,
        video: widget.videoEnabled,
      );
    } else {
      await widget.controller.acceptIncomingCall(
        widget.sessionId,
        video: widget.videoEnabled,
      );
    }

    // Video call: loudspeaker + keep screen on. Voice call: earpiece.
    _speakerOn = widget.videoEnabled;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
    if (widget.videoEnabled) WakelockPlus.enable();
    if (widget.controller.mediaManager.hasVideo) {
      widget.controller.videoActive.value = true;
    }

    if (!mounted) return;
    _localRenderer.srcObject = widget.controller.localStream;
    if (mounted) setState(() {});
  }

  void _onRemoteStreamChanged() {
    if (!mounted) return;
    _remoteRenderer.srcObject = widget.controller.remoteStream.value;
    setState(() {});
  }
  
  Future<void> _onVideoActive() async {
    if (!mounted || !widget.controller.videoActive.value) return;
    _speakerOn = true;
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
    WakelockPlus.enable();
    _localRenderer.srcObject = null;
    _localRenderer.srcObject = widget.controller.localStream;
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    await _toggleSpeakerOld();
    try {
      await _pipChannel.invokeMethod('speaker', _speakerOn);
    } catch (_) {}
  }

  Future<void> _toggleSpeakerOld() async {
    _speakerOn = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _toggleShare() async {
    final c = widget.controller;
    if (c.screenSharing.value) {
      await c.stopScreenShare();
    } else {
      final err = await c.startScreenShare();
      if (err != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }
    if (mounted) setState(() {});
  }

  void _openQuality() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => QualitySheet(
        controller: widget.controller,
        showVideo: widget.controller.videoActive.value,
      ),
    ).whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  String _choiceName(QualityChoice c) =>
      c.name[0].toUpperCase() + c.name.substring(1);

  String _qualityLabel() {
    final c = widget.controller;
    final a = _choiceName(c.audioChoice);
    if (!widget.controller.videoActive.value) return 'Audio $a';
    return 'Audio $a · Video ${_choiceName(c.videoChoice)}';
  }

  String _dataLabel(int bytes) {
    final mb = bytes / (1024 * 1024);
    return 'Data ${mb.toStringAsFixed(1)} MB';
  }

  bool _closing = false;

  /// The other phone pressed End: show "Call ended", then close.
  Future<void> _onPhaseChanged() async {
    if (widget.controller.phase.value != CallPhase.ended ||
        _closing ||
        widget.controller.silentEnd) {
      return;
    }
    _closing = true;
    await widget.controller.endCall(notifyPeer: false);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (_pip) _pipChannel.invokeMethod('leave').catchError((_) {});
    if (mounted) Navigator.of(context).pop();
  }

  /// Colour of the top panels: taken from the wallpaper, or the accent colour.
  Color _tint = Colors.black;

  Future<void> _loadTint() async {
    final wp = AppSettings.wallpaper.value;
    try {
      if (wp != null && File(wp).existsSync()) {
        final s = await ColorScheme.fromImageProvider(
          provider: ResizeImage(FileImage(File(wp)), width: 120),
          brightness: Brightness.dark,
        );
        if (mounted) setState(() => _tint = s.primaryContainer);
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _tint = Color(AppSettings.accent.value));
  }

  void _snackMsg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  /// The other person's UID, taken from the shared session id (me_them).
  String get _peerUid {
    final me = ContactController.current?.myUid ?? '';
    final s = widget.sessionId;
    if (me.isEmpty) return '';
    if (s.startsWith('${me}_')) return s.substring(me.length + 1);
    if (s.endsWith('_$me')) return s.substring(0, s.length - me.length - 1);
    return '';
  }

  /// Add participant: makes a group, rings the new people, tells the other
  /// phone, then both phones move from this call to the group call.
  Future<void> _addParticipant() async {
    final cc = ContactController.current;
    final peer = _peerUid;
    if (cc == null || peer.isEmpty) {
      _snackMsg('Cannot add people to this call.');
      return;
    }
    final picked = await pickFriends(context, cc, exclude: {peer});
    if (picked == null || picked.isEmpty || !mounted) return;
    final r = Random.secure();
    final rid = 'call_'
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${r.nextInt(1 << 30).toRadixString(36)}'
        '${r.nextInt(1 << 30).toRadixString(36)}';
    final video = widget.controller.videoActive.value;
    GroupRinger.ring(
      groupId: rid,
      groupName: 'Call',
      emoji: '📞',
      color: 0xFF0D9488,
      mode: 'friends',
      members: [peer, ...picked],
      video: video,
      fromUid: cc.myUid,
      only: picked,
    );
    await widget.controller.sendGroupInvite({
      'gid': rid,
      'name': 'Call',
      'emoji': '📞',
      'color': 0xFF0D9488,
      'mode': 'friends',
      'video': video,
    });
    await _goGroup(rid, 'Call', '📞', 0xFF0D9488, 'friends', video);
  }

  Future<void> _addParticipantOld() async {
    final cc = ContactController.current;
    final peer = _peerUid;
    if (cc == null || peer.isEmpty) {
      _snackMsg('Cannot add people to this call.');
      return;
    }
    final picked = await pickFriends(context, cc, exclude: {peer});
    if (picked == null || picked.isEmpty || !mounted) return;
    final t = DateTime.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final name = 'Group call $hh:$mm';
    final gc = GroupController(cc.myUid);
    final gid = await gc.createForCall(name, [peer, ...picked]);
    gc.dispose();
    if (gid == null) {
      _snackMsg('Could not start the group call.');
      return;
    }
    final video = widget.controller.videoActive.value;
    GroupRinger.ring(
      groupId: gid,
      groupName: name,
      emoji: '📞',
      color: 0xFF0D9488,
      mode: 'friends',
      members: [peer, ...picked],
      video: video,
      fromUid: cc.myUid,
      only: picked,
    );
    await widget.controller.sendGroupInvite({
      'gid': gid,
      'name': name,
      'emoji': '📞',
      'color': 0xFF0D9488,
      'mode': 'friends',
      'video': video,
    });
    await _goGroup(gid, name, '📞', 0xFF0D9488, 'friends', video);
  }

  void _onGroupInvite() {
    final g = widget.controller.groupInvite.value;
    if (g == null || !mounted) return;
    _goGroup(
      (g['gid'] ?? '').toString(),
      (g['name'] ?? 'Group call').toString(),
      (g['emoji'] ?? '📞').toString(),
      (g['color'] as num?)?.toInt() ?? 0xFF0D9488,
      (g['mode'] ?? 'friends').toString(),
      g['video'] == true,
    );
  }

  /// Ends this 1-to-1 call quietly and opens the group call in its place.
  Future<void> _goGroup(String gid, String name, String emoji, int color,
      String mode, bool video) async {
    final cc = ContactController.current;
    if (_closing || cc == null || gid.isEmpty) return;
    _closing = true;
    widget.controller.silentEnd = true;
    await widget.controller.endCall(notifyPeer: false);
    if (_pip) _pipChannel.invokeMethod('leave').catchError((_) {});
    if (!mounted) return;
    setState(() {
      _roomGc = GroupController(cc.myUid);
      _roomName = name;
      _roomEmoji = emoji;
      _roomColor = color;
      _roomMode = mode;
      _roomVideo = video;
      _roomId = gid;
    });
  }

  Future<void> _goGroupOld(String gid, String name, String emoji, int color,
      String mode, bool video) async {
    final cc = ContactController.current;
    if (_closing || cc == null || gid.isEmpty) return;
    _closing = true;
    await widget.controller.endCall(notifyPeer: false);
    if (_pip) _pipChannel.invokeMethod('leave').catchError((_) {});
    if (!mounted) return;
    final gc = GroupController(cc.myUid);
    await gc.refresh();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          groupId: gid,
          groupName: name,
          video: video,
          emoji: emoji,
          color: color,
          mode: mode,
          groupController: gc,
          contactController: cc,
          myUid: cc.myUid,
        ),
      ),
    );
  }

  Future<void> _endCall() async {
    _closing = true;
    await widget.controller.endCall();
    if (_pip) _pipChannel.invokeMethod('leave').catchError((_) {});
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.controller.remoteStream.removeListener(_onRemoteStreamChanged);
    widget.controller.phase.removeListener(_onPhaseChanged);
    widget.controller.videoActive.removeListener(_onVideoActive);
    widget.controller.phase.removeListener(_syncPip);
    widget.controller.groupInvite.removeListener(_onGroupInvite);
    widget.controller.remoteOnHold.removeListener(_syncHoldSound);
    _holdPlayer.stop();
    _holdPlayer.dispose();
    widget.controller.videoActive.removeListener(_syncPip);
    _pipChannel.setMethodCallHandler(null);
    _pipChannel.invokeMethod('setAuto', false).catchError((_) {});
    _localRenderer.dispose();
    widget.controller.speakerOn = _speakerOn;
    _remoteRenderer.dispose();
    WakelockPlus.disable();
    LockScreen.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_roomId != null) {
      return GroupCallScreen(
        groupId: _roomId!,
        groupName: _roomName,
        video: _roomVideo,
        emoji: _roomEmoji,
        color: _roomColor,
        mode: _roomMode,
        groupController: _roomGc!,
        contactController: ContactController.current!,
        myUid: ContactController.current!.myUid,
      );
    }
    if (_pip) return _pipView();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.controller.phase.value == CallPhase.active) {
          Navigator.of(context).pop('minimize');
        } else {
          _endCall();
        }
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote video fills the screen
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.controller.remoteScreenOn,
                builder: (context, shared, _) => RTCVideoView(
                  _remoteRenderer,
                  objectFit: shared
                      ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                      : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

            // Avatar + blurred photo while there is no remote video
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  widget.controller.remoteStream,
                  widget.controller.remoteCameraOn,
                ]),
                builder: (context, _) {
                  final s = widget.controller.remoteStream.value;
                  final hasVideo =
                      s != null && s.getVideoTracks().isNotEmpty;
                  if (hasVideo && widget.controller.remoteCameraOn.value) {
                    return const SizedBox.shrink();
                  }
                  final has = widget.photoUrl != null &&
                      widget.photoUrl!.isNotEmpty;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: const Color(0xFF042F2E)),
                      if (AppSettings.wallpaper.value != null &&
                          AppSettings.wallpaperOnCall.value) ...[
                        RepaintBoundary(
                          child: Image.file(
                            File(AppSettings.wallpaper.value!),
                            fit: BoxFit.cover,
                            cacheWidth:
                                AppSettings.wallpaperBlur.value ? 48 : 1080,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        Container(color: Colors.black45),
                      ] else ...[
                        if (has) BlurredPhoto(url: widget.photoUrl!),
                        if (has) Container(color: Colors.black45),
                      ],
                      Center(
                        child: UserAvatar(
                          name: widget.contactName,
                          photoUrl: widget.photoUrl,
                          radius: 64,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Dark fade at top and bottom so text/buttons show on bright video
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black54,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black54,
                      ],
                      stops: [0.0, 0.25, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Add participant button (top right)
            Positioned(
              top: 4,
              right: 4,
              child: ValueListenableBuilder<CallPhase>(
                valueListenable: widget.controller.phase,
                builder: (context, phase, _) => phase == CallPhase.active
                    ? IconButton(
                        tooltip: 'Add participant',
                        onPressed: _addParticipant,
                        icon: const Icon(
                          Icons.person_add_alt_1,
                          color: Colors.white,
                          size: 26,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // Minimize button
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                tooltip: 'Minimize',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),

            // Contact name + call phase at top
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    widget.contactName,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  ValueListenableBuilder<CallPhase>(
                    valueListenable: widget.controller.phase,
                    builder: (context, phase, _) =>
                        ValueListenableBuilder<String?>(
                      valueListenable: widget.hint ?? _noHint,
                      builder: (context, h, _) => Text(
                        (phase == CallPhase.connecting && h != null)
                            ? h
                            : _phaseLabel(phase),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // On hold / muted notices
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    widget.controller.onHold,
                    widget.controller.remoteOnHold,
                    widget.controller.remoteMicOn,
                  ]),
                  builder: (context, _) {
                    final c = widget.controller;
                    final mine = c.onHold.value;
                    final theirs = c.remoteOnHold.value;
                    final muted = !c.remoteMicOn.value;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (mine || theirs)
                          Container(
                            color: Colors.black54,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.pause_circle_filled,
                                    color: Colors.white,
                                    size: 72,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    mine
                                        ? 'Call on hold'
                                        : '${widget.contactName} put you on hold',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (muted)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 310,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.mic_off,
                                      color: Colors.redAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${widget.contactName} is muted',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // Quality button + data counter
            Positioned(
              top: 80,
              left: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _openQuality,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _tint.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _qualityLabel(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.controller.voiceBoost,
                    builder: (context, on, _) => GestureDetector(
                      onTap: () => widget.controller.setVoiceBoost(!on),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: on
                              ? Colors.white.withOpacity(0.92)
                              : _tint.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.record_voice_over,
                                size: 16,
                                color: on ? Colors.black : Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              'Voice boost',
                              style: TextStyle(
                                color: on ? Colors.black : Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: widget.controller.dataBytes,
                    builder: (context, bytes, _) => Text(
                      _dataLabel(bytes),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Debug readout (only with SHOW_DEBUG)
            if (const bool.fromEnvironment('SHOW_DEBUG'))
            Positioned(
              top: 150,
              left: 16,
              child: ValueListenableBuilder<String>(
                valueListenable: widget.controller.debugText,
                builder: (context, t, _) => Text(
                  t,
                  style: const TextStyle(
                    color: Colors.yellowAccent,
                    fontSize: 11,
                  ),
                ),
              ),
            ),

            // Weak-network hint
            Positioned(
              left: 16,
              right: 16,
              bottom: 250,
              child: ValueListenableBuilder<bool>(
                valueListenable: widget.controller.weakNetwork,
                builder: (context, weak, _) {
                  final c = widget.controller;
                  bool notLow(QualityChoice q) =>
                      q == QualityChoice.medium ||
                      q == QualityChoice.high ||
                      q == QualityChoice.extreme;
                  final show =
                      weak && (notLow(c.audioChoice) || notLow(c.videoChoice));
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: !show
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Weak connection. Switch to Low?',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    c.setAudioChoice(QualityChoice.low);
                                    c.setVideoChoice(QualityChoice.low);
                                    setState(() {});
                                  },
                                  child: const Text('Switch'),
                                ),
                              ],
                            ),
                          ),
                  );
                },
              ),
            ),

            // Local video preview, small corner box
            if (widget.controller.mediaManager.hasVideo &&
                widget.controller.cameraEnabled)
            Positioned(
              top: 80,
              right: 16,
              width: 110,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(
                  _localRenderer,
                  mirror: _frontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

            // Compact controls (video calls) or the full controls (voice calls)
            if (_compact) _compactBar(),
            if (!_compact)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Glass(
                    blur: 14,
                    tint: _tint,
                    opacity: 0.30,
                    borderRadius: BorderRadius.circular(36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        AnimatedCallButton(
                          icon: widget.controller.micEnabled
                              ? Icons.mic
                              : Icons.mic_off,
                          highlighted: !widget.controller.micEnabled,
                          onPressed: () {
                            widget.controller.toggleMic();
                            setState(() {});
                          },
                        ),
                        AnimatedCallButton(
                          icon: (widget.controller.mediaManager.hasVideo &&
                                  widget.controller.cameraEnabled)
                              ? Icons.videocam
                              : Icons.videocam_off,
                          highlighted:
                              !(widget.controller.mediaManager.hasVideo &&
                                  widget.controller.cameraEnabled),
                          onPressed: () async {
                            final c = widget.controller;
                            if (!c.mediaManager.hasVideo) {
                              await c.enableVideo();
                              _localRenderer.srcObject = null;
                              _localRenderer.srcObject = c.localStream;
                            } else {
                              await c.toggleCamera();
                              _localRenderer.srcObject = null;
                              _localRenderer.srcObject = c.localStream;
                            }
                            if (mounted) setState(() {});
                          },
                        ),
                        AnimatedCallButton(
                          icon: _speakerOn ? Icons.volume_up : Icons.hearing,
                          highlighted: _speakerOn,
                          onPressed: _toggleSpeaker,
                        ),
                        if (widget.controller.mediaManager.hasVideo &&
                            !widget.controller.screenSharing.value)
                          AnimatedCallButton(
                            icon: Icons.cameraswitch,
                            onPressed: () {
                              widget.controller.switchCamera();
                              setState(() => _frontCamera = !_frontCamera);
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Glass(
                    blur: 14,
                    tint: Colors.black,
                    opacity: 0.30,
                    borderRadius: BorderRadius.circular(36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedCallButton(
                          icon: widget.controller.onHold.value
                              ? Icons.play_arrow
                              : Icons.pause,
                          highlighted: widget.controller.onHold.value,
                          onPressed: () async {
                            await widget.controller.toggleHold();
                            if (mounted) setState(() {});
                          },
                        ),
                        const SizedBox(width: 24),
                        AnimatedCallButton(
                          icon: widget.controller.screenSharing.value
                              ? Icons.stop_screen_share
                              : Icons.screen_share,
                          highlighted: widget.controller.screenSharing.value,
                          onPressed: _toggleShare,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(34),
                      onTap: _endCall,
                      child: Container(
                        width: double.infinity,
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(34),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.call_end, color: Colors.white, size: 26),
                            SizedBox(width: 10),
                            Text(
                              'End call',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  bool get _compact => widget.controller.mediaManager.hasVideo;

  Future<void> _toggleCam() async {
    final c = widget.controller;
    if (!c.mediaManager.hasVideo) {
      await c.enableVideo();
    } else {
      await c.toggleCamera();
    }
    _localRenderer.srcObject = null;
    _localRenderer.srcObject = c.localStream;
    if (mounted) setState(() {});
  }

  Widget _roundBox(IconData icon, bool hi) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hi ? Colors.white : Colors.white.withOpacity(0.16),
        ),
        child: Icon(icon, size: 22, color: hi ? Colors.black87 : Colors.white),
      );

  Widget _round(IconData icon, bool hi, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: _roundBox(icon, hi),
      );

  Widget _endRound() => GestureDetector(
        onTap: _endCall,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
            ),
          ),
          child: const Icon(Icons.call_end, color: Colors.white, size: 24),
        ),
      );

  Widget _moreMenu() {
    final c = widget.controller;
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (v) async {
        if (v == 'hold') {
          await c.toggleHold();
          if (mounted) setState(() {});
        } else if (v == 'share') {
          await _toggleShare();
        } else if (v == 'quality') {
          _openQuality();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'hold',
          child: Text(c.onHold.value ? 'Resume call' : 'Hold call'),
        ),
        PopupMenuItem(
          value: 'share',
          child: Text(
              c.screenSharing.value ? 'Stop screen share' : 'Share screen'),
        ),
        const PopupMenuItem(value: 'quality', child: Text('Call quality')),
      ],
      child: _roundBox(Icons.more_vert, false),
    );
  }

  Widget _compactBar() {
    final c = widget.controller;
    final camOn = c.mediaManager.hasVideo && c.cameraEnabled;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 16,
      child: Glass(
        blur: 14,
        tint: _tint,
        opacity: 0.30,
        borderRadius: BorderRadius.circular(40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _round(c.micEnabled ? Icons.mic : Icons.mic_off, !c.micEnabled,
                () {
              c.toggleMic();
              setState(() {});
            }),
            _round(camOn ? Icons.videocam : Icons.videocam_off, !camOn,
                _toggleCam),
            _round(_speakerOn ? Icons.volume_up : Icons.hearing, _speakerOn,
                _toggleSpeaker),
            if (!c.screenSharing.value)
              _round(Icons.cameraswitch, false, () {
                c.switchCamera();
                setState(() => _frontCamera = !_frontCamera);
              }),
            _moreMenu(),
            _endRound(),
          ],
        ),
      ),
    );
  }

  String _phaseLabel(CallPhase phase) {
    switch (phase) {
      case CallPhase.connecting:
        return 'Connecting...';
      case CallPhase.active:
        return 'Connected';
      case CallPhase.ended:
        return widget.controller.endLabel;
      default:
        return '';
    }
  }
}

