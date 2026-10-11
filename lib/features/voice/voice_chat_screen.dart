import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/glass.dart';
import '../../utils/settings/app_settings.dart';
import '../../utils/user_avatar.dart';
import 'voice_service.dart';

class VoiceChatScreen extends StatefulWidget {
  final String contactName;
  final String contactUid;
  final String myUid;
  final String? photoUrl;

  const VoiceChatScreen({
    super.key,
    required this.contactName,
    required this.contactUid,
    required this.myUid,
    this.photoUrl,
  });

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen> {
  late final VoiceService _svc =
      VoiceService(myUid: widget.myUid, peerUid: widget.contactUid);
  final _player = AudioPlayer();
  final _pos = ValueNotifier<double>(0);
  final _level = ValueNotifier<double>(0);
  final _subs = <StreamSubscription>[];
  Duration _dur = Duration.zero;
  String? _playingId;
  String? _loadingId;
  bool _recording = false;
  bool _sending = false;
  int _recSeconds = 0;
  Timer? _timer;
  StreamSubscription? _ampSub;

  @override
  void initState() {
    super.initState();
    _svc.start();
    _subs.add(_player.onDurationChanged.listen((d) => _dur = d));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (_dur.inMilliseconds > 0) {
        _pos.value =
            (p.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);
      }
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      _pos.value = 0;
      if (mounted) setState(() => _playingId = null);
    }));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    () async {
      if (_recording) await _svc.cancelRecording();
      _svc.dispose();
    }();
    _pos.dispose();
    _level.dispose();
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ---------- recording ----------

  Future<void> _startRec() async {
    await _player.stop();
    final ok = await _svc.startRecording();
    if (!ok) {
      _snack('Microphone permission is needed.');
      return;
    }
    HapticFeedback.mediumImpact();
    _recSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recSeconds++);
      if (_recSeconds >= VoiceService.maxSeconds) _finishRec(send: true);
    });
    _ampSub = _svc.amplitude(const Duration(milliseconds: 120)).listen((a) {
      _level.value = ((a.current + 50) / 50).clamp(0.0, 1.0);
    });
    setState(() {
      _recording = true;
      _playingId = null;
    });
  }

  Future<void> _finishRec({required bool send}) async {
    if (!_recording) return;
    _timer?.cancel();
    _ampSub?.cancel();
    _level.value = 0;
    setState(() => _recording = false);
    if (!send) {
      await _svc.cancelRecording();
      return;
    }
    final r = await _svc.stopRecording();
    if (r == null) {
      _snack('Too short. Record for at least a second.');
      return;
    }
    if (mounted) setState(() => _sending = true);
    final err = await _svc.send(r.file, r.seconds);
    if (mounted) setState(() => _sending = false);
    if (err != null) {
      _snack(err);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  // ---------- playback ----------

  Future<void> _toggle(VoiceMessage m) async {
    if (_playingId == m.id) {
      await _player.stop();
      _pos.value = 0;
      setState(() => _playingId = null);
      return;
    }
    setState(() => _loadingId = m.id);
    final f = await _svc.fileFor(m);
    if (!mounted) return;
    setState(() => _loadingId = null);
    if (f == null) {
      _snack('This message is no longer available on this phone.');
      return;
    }
    try {
      await _player.stop();
      _pos.value = 0;
      await _player.play(DeviceFileSource(f.path));
      setState(() => _playingId = m.id);
    } catch (_) {
      _snack('Could not play this message.');
    }
  }

  Future<void> _confirmDelete(VoiceMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete voice message?'),
        content: const Text('It is removed for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (_playingId == m.id) await _player.stop();
      await _svc.delete(m);
    }
  }

  // ---------- pieces ----------

  Widget _background() {
    final wp = AppSettings.wallpaper.value;
    final s = Theme.of(context).colorScheme;
    if (wp != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(wp), fit: BoxFit.cover),
          ColoredBox(color: s.surface.withOpacity(0.55)),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [s.primaryContainer.withOpacity(0.6), s.surface],
        ),
      ),
    );
  }

  Widget _bubble(VoiceMessage m) {
    final mine = m.fromUid == widget.myUid;
    final s = Theme.of(context).colorScheme;
    final accent = Color(AppSettings.accent.value);
    final fg = mine ? Colors.white : s.onSurface;
    final playing = _playingId == m.id;
    final loading = _loadingId == m.id;
    final isNew = !mine && m.playedAt == null;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _confirmDelete(m),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: mine ? accent : s.surface.withOpacity(0.78),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(mine ? 20 : 6),
              bottomRight: Radius.circular(mine ? 6 : 20),
            ),
            border: mine ? null : Border.all(color: s.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _toggle(m),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: mine
                            ? Colors.white.withOpacity(0.25)
                            : accent.withOpacity(0.15),
                      ),
                      child: loading
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: fg,
                              ),
                            )
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                                key: ValueKey(playing),
                                color: mine ? Colors.white : accent,
                                size: 28,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _pos,
                          builder: (context, v, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: playing ? v : 0,
                              minHeight: 5,
                              backgroundColor: fg.withOpacity(0.25),
                              valueColor: AlwaysStoppedAnimation(
                                mine ? Colors.white : accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _fmt(m.seconds),
                          style: TextStyle(color: fg, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  if (isNew) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hm(m.createdAt),
                    style: TextStyle(color: fg.withOpacity(0.7), fontSize: 11),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 6),
                    Icon(
                      m.playedAt != null ? Icons.done_all : Icons.done,
                      size: 14,
                      color: Colors.white.withOpacity(0.85),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      m.playedAt != null ? 'Heard' : 'Sent',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    final s = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<VoiceMessage>>(
      valueListenable: _svc.messages,
      builder: (context, list, _) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_none, size: 56, color: s.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    'Send ${widget.contactName} a quick voice message.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.onSurface, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'It reaches them even if they are offline, and it is '
                    'removed from the cloud once they have listened.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          itemCount: list.length,
          itemBuilder: (context, i) => _bubble(list[list.length - 1 - i]),
        );
      },
    );
  }

  Widget _wave() {
    return ValueListenableBuilder<double>(
      valueListenable: _level,
      builder: (context, lv, _) => SizedBox(
        height: 34,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 18; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 3,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height: 4 +
                    lv *
                        28 *
                        (0.35 +
                            0.65 *
                                ((math.sin(i * 0.9 + _recSeconds * 1.7) + 1) /
                                    2)),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final accent = Color(AppSettings.accent.value);
    final s = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_sending)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('Sending...',
                        style: TextStyle(color: s.onSurfaceVariant)),
                  ],
                ),
              ),
            Glass(
              blur: 12,
              tint: s.surface,
              opacity: 0.55,
              borderRadius: BorderRadius.circular(34),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _recording
                    ? Row(
                        key: const ValueKey('rec'),
                        children: [
                          IconButton(
                            tooltip: 'Cancel',
                            onPressed: () => _finishRec(send: false),
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent, size: 28),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _wave(),
                                Text(
                                  '${_fmt(_recSeconds)} / ${_fmt(VoiceService.maxSeconds)}',
                                  style: TextStyle(
                                    color: s.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _finishRec(send: true),
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent,
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withOpacity(0.45),
                                    blurRadius: 14,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.send_rounded,
                                  color: Colors.white),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: const ValueKey('idle'),
                        children: [
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Tap the mic to record',
                              style: TextStyle(color: s.onSurfaceVariant),
                            ),
                          ),
                          GestureDetector(
                            onTap: _sending ? null : _startRec,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [accent.withOpacity(0.75), accent],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withOpacity(0.45),
                                    blurRadius: 14,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.mic,
                                  color: Colors.white, size: 28),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(
              name: widget.contactName,
              photoUrl: widget.photoUrl,
              radius: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.contactName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _background(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(child: _list()),
                _bottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}