import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../utils/settings/app_settings.dart';
import '../../utils/user_avatar.dart';
import '../../utils/glass.dart';
import '../call/animated_call_button.dart';
import '../../core/signaling/group_ring_service.dart';
import '../contacts/contact_controller.dart';
import 'group_controller.dart';
import 'groups_screen.dart';

const _reactions = ['👍', '❤️', '😂', '🎉', '🔥', '👏'];

class _Float {
  final int id;
  final String emoji;
  final double x;
  _Float(this.id, this.emoji, this.x);
}

class GroupCallScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final bool video;
  final String emoji;
  final int color;
  final String mode; // 'friends' or 'work'
  final GroupController groupController;
  final ContactController contactController;
  final String myUid;

  const GroupCallScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.video,
    required this.groupController,
    required this.contactController,
    required this.myUid,
    this.emoji = '👥',
    this.color = 0xFF0D9488,
    this.mode = 'friends',
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final Room _room = Room(
    roomOptions: RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      defaultCameraCaptureOptions:
          CameraCaptureOptions(params: VideoParametersPresets.h360_169),
      defaultVideoPublishOptions: VideoPublishOptions(
        simulcast: true,
        videoEncoding: VideoEncoding(maxBitrate: 500000, maxFramerate: 24),
      ),
    ),
  );
  late final EventsListener<RoomEvent> _events = _room.createListener();

  String? _error;
  bool _joined = false;
  bool _leaving = false;
  bool _mic = true;
  late bool _cam = widget.video;
  late bool _speaker = widget.video;
  bool _handUp = false;
  bool _showReact = false;
  String? _pinned;
  final Set<String> _raised = {};
  final List<_Float> _floats = [];
  int _floatId = 0;
  Timer? _clock;
  int _seconds = 0;

  bool get _work => widget.mode == 'work';
  Color get _base => Color(widget.color);

  GroupModel? get _group => widget.groupController.groups.value
      .where((x) => x.id == widget.groupId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _room.addListener(_onChange);
    widget.contactController.photos.addListener(_onChange);
    widget.groupController.groups.addListener(_onChange);
    _events
      ..on<DataReceivedEvent>(_onData)
      ..on<RoomDisconnectedEvent>((_) {
        if (mounted && !_leaving) _leave();
      });
    WakelockPlus.enable();
    _join();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _join() async {
    try {
      final perms = await [
        Permission.microphone,
        if (widget.video) Permission.camera,
      ].request();
      if (perms[Permission.microphone] != PermissionStatus.granted) {
        throw 'Microphone permission is needed.';
      }
      final res = await Supabase.instance.client.functions
          .invoke('livekit-token', body: {'group_id': widget.groupId});
      final d = res.data;
      if (d is! Map || d['token'] == null) {
        throw (d is Map ? d['error'] : null) ?? 'Could not get a call token.';
      }
      await _room.connect(d['url'] as String, d['token'] as String);
      await _room.localParticipant?.setMicrophoneEnabled(true);
      if (widget.video) {
        await _room.localParticipant?.setCameraEnabled(true);
      }
      try {
        await Hardware.instance.setSpeakerphoneOn(_speaker);
      } catch (_) {}
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
      if (mounted) setState(() => _joined = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _send(Map<String, dynamic> m) async {
    try {
      await _room.localParticipant
          ?.publishData(utf8.encode(jsonEncode(m)), reliable: true);
    } catch (_) {}
  }

  void _onData(DataReceivedEvent e) {
    try {
      final m = jsonDecode(utf8.decode(e.data)) as Map;
      final from = e.participant?.identity ?? '';
      if (m['t'] == 'react') {
        _addFloat(m['e'].toString());
      } else if (m['t'] == 'hand') {
        if (m['v'] == true) {
          _raised.add(from);
        } else {
          _raised.remove(from);
        }
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _addFloat(String e) {
    if (!mounted) return;
    final id = _floatId++;
    final x = 0.08 + ((id * 37) % 76) / 100;
    setState(() => _floats.add(_Float(id, e, x)));
    Future.delayed(const Duration(milliseconds: 2700), () {
      if (mounted) setState(() => _floats.removeWhere((f) => f.id == id));
    });
  }

  void _react(String e) {
    _addFloat(e);
    _send({'t': 'react', 'e': e});
  }

  void _toggleHand() {
    _handUp = !_handUp;
    final me = _room.localParticipant?.identity ?? widget.myUid;
    if (_handUp) {
      _raised.add(me);
    } else {
      _raised.remove(me);
    }
    _send({'t': 'hand', 'v': _handUp});
    setState(() {});
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addPeople() async {
    final g = _group;
    if (g == null) return;
    final uids = await pickFriends(
      context,
      widget.contactController,
      exclude: g.members.toSet(),
    );
    if (uids == null || uids.isEmpty) return;
    final err = await widget.groupController.addMembers(g.id, uids);
    if (err == null) {
      GroupRinger.ring(
        groupId: g.id,
        groupName: g.name,
        emoji: g.emoji,
        color: g.color,
        mode: g.mode,
        members: g.members,
        video: widget.video,
        fromUid: widget.myUid,
        only: uids,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Added to the group')),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _room.removeListener(_onChange);
    widget.contactController.photos.removeListener(_onChange);
    widget.groupController.groups.removeListener(_onChange);
    _events.dispose();
    WakelockPlus.disable();
    () async {
      await _room.disconnect();
      await _room.dispose();
    }();
    super.dispose();
  }

  // ---------- pieces ----------

  VideoTrack? _videoOf(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (pub.source == TrackSource.camera &&
          !pub.muted &&
          pub.track != null) {
        return pub.track as VideoTrack;
      }
    }
    return null;
  }

  Widget _tile(Participant p) {
    final v = _videoOf(p);
    final isMe = p is LocalParticipant;
    final name = isMe ? 'You' : (p.name.isNotEmpty ? p.name : p.identity);
    final photos = widget.contactController.photos.value;
    if (!isMe && !photos.containsKey(p.identity)) {
      widget.contactController.fetchPhoto(p.identity);
    }
    final speaking = p.isSpeaking;
    final pinned = _pinned == p.identity;
    return GestureDetector(
      onTap: () => setState(() => _pinned = pinned ? null : p.identity),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: speaking ? Colors.white : Colors.white24,
            width: speaking ? 3 : 1,
          ),
          boxShadow: speaking
              ? [BoxShadow(color: _base.withOpacity(0.8), blurRadius: 16)]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.black38,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (v != null)
                  VideoTrackRenderer(v, fit: VideoViewFit.cover)
                else
                  Center(
                    child: UserAvatar(
                      name: name,
                      photoUrl: isMe ? null : photos[p.identity],
                      radius: 36,
                    ),
                  ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: 8,
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!p.isMicrophoneEnabled())
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.mic_off,
                                      size: 14, color: Colors.redAccent),
                                ),
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_raised.contains(p.identity))
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: const Text('✋', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                if (pinned)
                  const Positioned(
                    top: 8,
                    left: 8,
                    child: Icon(Icons.push_pin, color: Colors.white, size: 18),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout(List<Participant> all) {
    if (all.length == 1) {
      return Padding(padding: const EdgeInsets.all(8), child: _tile(all[0]));
    }
    final pinned = all.where((p) => p.identity == _pinned).firstOrNull;
    if (pinned != null) {
      final others = all.where((p) => p != pinned).toList();
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: _tile(pinned),
            ),
          ),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(width: 90, child: _tile(others[i])),
            ),
          ),
        ],
      );
    }
    if (all.length == 2) {
      return Column(
        children: [
          for (final p in all)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _tile(p),
              ),
            ),
        ],
      );
    }
    return GridView.count(
      padding: const EdgeInsets.all(8),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.85,
      children: [for (final p in all) _tile(p)],
    );
  }

  Widget _background() {
    final wp = AppSettings.wallpaper.value;
    final useWp = wp != null && AppSettings.wallpaperOnCall.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(_base, Colors.black, 0.55)!,
                Color.lerp(_base, Colors.black, 0.88)!,
              ],
            ),
          ),
        ),
        if (useWp) ...[
          Image.file(File(wp), fit: BoxFit.cover),
          Container(color: Colors.black54),
        ],
      ],
    );
  }

  String _time() {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _topBar(int count) {
    final canAdd = _group?.isOwner == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Leave',
            onPressed: _leave,
            icon: const Icon(Icons.keyboard_arrow_down,
                color: Colors.white, size: 30),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${widget.emoji}  ${widget.groupName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 19),
                ),
                Text(
                  _joined ? '$count in call · ${_time()}' : 'Connecting...',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 48,
            child: canAdd
                ? IconButton(
                    tooltip: 'Add participants',
                    onPressed: _addPeople,
                    icon: const Icon(Icons.person_add_alt_1,
                        color: Colors.white),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    final lp = _room.localParticipant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showReact && !_work)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Glass(
                blur: 14,
                tint: Colors.black,
                opacity: 0.35,
                borderRadius: BorderRadius.circular(30),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final e in _reactions)
                      GestureDetector(
                        onTap: () => _react(e),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(e, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Glass(
            blur: 14,
            tint: Colors.black,
            opacity: 0.30,
            borderRadius: BorderRadius.circular(36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                AnimatedCallButton(
                  icon: _mic ? Icons.mic : Icons.mic_off,
                  highlighted: !_mic,
                  onPressed: () async {
                    _mic = !_mic;
                    await lp?.setMicrophoneEnabled(_mic);
                    if (mounted) setState(() {});
                  },
                ),
                AnimatedCallButton(
                  icon: _cam ? Icons.videocam : Icons.videocam_off,
                  highlighted: !_cam,
                  onPressed: () async {
                    _cam = !_cam;
                    await lp?.setCameraEnabled(_cam);
                    if (mounted) setState(() {});
                  },
                ),
                AnimatedCallButton(
                  icon: _speaker ? Icons.volume_up : Icons.hearing,
                  highlighted: _speaker,
                  onPressed: () async {
                    _speaker = !_speaker;
                    try {
                      await Hardware.instance.setSpeakerphoneOn(_speaker);
                    } catch (_) {}
                    if (mounted) setState(() {});
                  },
                ),
                if (_cam)
                  AnimatedCallButton(
                    icon: Icons.cameraswitch,
                    onPressed: () async {
                      try {
                        for (final pub in lp!.videoTrackPublications) {
                          final t = pub.track;
                          if (t is LocalVideoTrack &&
                              pub.source == TrackSource.camera) {
                            final back = t.currentOptions is CameraCaptureOptions &&
                                (t.currentOptions as CameraCaptureOptions)
                                        .cameraPosition ==
                                    CameraPosition.back;
                            await t.setCameraPosition(
                              back ? CameraPosition.front : CameraPosition.back,
                            );
                          }
                        }
                      } catch (_) {}
                    },
                  ),
                if (_work)
                  AnimatedCallButton(
                    icon: Icons.back_hand_outlined,
                    highlighted: _handUp,
                    onPressed: _toggleHand,
                  )
                else
                  AnimatedCallButton(
                    icon: Icons.emoji_emotions_outlined,
                    highlighted: _showReact,
                    onPressed: () => setState(() => _showReact = !_showReact),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(34),
              onTap: _leave,
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
                      'Leave call',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = <Participant>[
      if (_room.localParticipant != null) _room.localParticipant!,
      ..._room.remoteParticipants.values,
    ];
    final size = MediaQuery.of(context).size;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _background(),
            SafeArea(
              child: Column(
                children: [
                  _topBar(all.length),
                  Expanded(
                    child: _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                        : !_joined
                            ? const Center(child: CircularProgressIndicator())
                            : _layout(all),
                  ),
                  _controls(),
                ],
              ),
            ),
            IgnorePointer(
              child: Stack(
                children: [
                  for (final f in _floats)
                    Positioned(
                      key: ValueKey(f.id),
                      left: f.x * size.width,
                      bottom: 170,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 2600),
                        curve: Curves.easeOut,
                        builder: (context, t, child) => Transform.translate(
                          offset: Offset(0, -t * size.height * 0.55),
                          child: Opacity(opacity: 1 - t, child: child),
                        ),
                        child: Text(f.emoji,
                            style: const TextStyle(fontSize: 42)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}