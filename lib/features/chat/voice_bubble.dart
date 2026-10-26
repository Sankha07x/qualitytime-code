import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../utils/settings/app_settings.dart';
import '../voice/voice_service.dart';
import 'bubble_shell.dart';

/// One audio player shared by all voice bubbles (only one plays at a time).
class VoicePlayerController extends ChangeNotifier {
  final _p = AudioPlayer();
  final pos = ValueNotifier<double>(0);
  final _subs = <StreamSubscription>[];
  Duration _dur = Duration.zero;
  String? playingId;
  VoiceMessage? _once;
  VoiceService? _onceSvc;
  String? loadingId;
  bool _disposed = false;

  VoicePlayerController() {
    _subs.add(_p.onDurationChanged.listen((d) => _dur = d));
    _subs.add(_p.onPositionChanged.listen((p) {
      if (_dur.inMilliseconds > 0) {
        pos.value = (p.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);
      }
    }));
    _subs.add(_p.onPlayerComplete.listen((_) {
      _finishOnce();
      pos.value = 0;
      playingId = null;
      _tell();
    }));
  }

  void _finishOnce() {
    final m = _once;
    final s = _onceSvc;
    _once = null;
    _onceSvc = null;
    if (m != null && s != null) s.consume(m);
  }

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() async {
    _finishOnce();
    await _p.stop();
    pos.value = 0;
    playingId = null;
    _tell();
  }

  /// Returns an error text, or null.
  Future<String?> toggle(VoiceMessage m, VoiceService svc) async {
    if (playingId == m.id) {
      await stop();
      return null;
    }
    _finishOnce();
    loadingId = m.id;
    _tell();
    final f = await svc.fileFor(m);
    loadingId = null;
    if (f == null) {
      _tell();
      return 'This message is no longer available on this phone.';
    }
    try {
      await _p.stop();
      pos.value = 0;
      await _p.play(DeviceFileSource(f.path));
      if (m.viewOnce && m.toUid == svc.myUid) {
        _once = m;
        _onceSvc = svc;
      }
      playingId = m.id;
      _tell();
      return null;
    } catch (_) {
      _tell();
      return 'Could not play this message.';
    }
  }

  @override
  void dispose() {
    _finishOnce();
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    pos.dispose();
    super.dispose();
  }
}

class VoiceBubble extends StatelessWidget {
  final VoiceMessage m;
  final bool mine;
  final VoicePlayerController player;
  final VoiceService svc;
  final void Function(String) onError;
  final VoidCallback onLongPress;

  const VoiceBubble({
    super.key,
    required this.m,
    required this.mine,
    required this.player,
    required this.svc,
    required this.onError,
    required this.onLongPress,
  });

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final accent = Color(AppSettings.accent.value);
    final fg = bubbleFg(context, mine);
    final isNew = !mine && m.playedAt == null;
    return BubbleShell(
      mine: mine,
      onLongPress: onLongPress,
      child: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          final playing = player.playingId == m.id;
          final loading = player.loadingId == m.id;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      if (m.viewOnce &&
                          (mine || (m.playedAt != null && !playing))) {
                        return;
                      }
                      final e = await player.toggle(m, svc);
                      if (e != null) onError(e);
                    },
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
                                  strokeWidth: 2.5, color: fg),
                            )
                          : Icon(
                              playing
                                  ? Icons.pause
                                  : !m.viewOnce
                                      ? Icons.play_arrow
                                      : (m.playedAt != null
                                          ? Icons.check_circle_outline
                                          : Icons.looks_one_outlined),
                              color: mine ? Colors.white : accent,
                              size: 28,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: player.pos,
                          builder: (context, v, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: playing ? v : 0,
                              minHeight: 5,
                              backgroundColor: fg.withOpacity(0.25),
                              valueColor: AlwaysStoppedAnimation(
                                  mine ? Colors.white : accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                            m.viewOnce
                                ? (m.playedAt != null
                                    ? 'Opened'
                                    : 'View once  ${_fmt(m.seconds)}')
                                : _fmt(m.seconds),
                            style: TextStyle(color: fg, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (isNew) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 9,
                      height: 9,
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(hm(m.createdAt),
                      style: TextStyle(
                          color: fg.withOpacity(0.7), fontSize: 11)),
                  if (mine) ...[
                    const SizedBox(width: 6),
                    Icon(m.playedAt != null ? Icons.done_all : Icons.done,
                        size: 14, color: Colors.white.withOpacity(0.85)),
                    const SizedBox(width: 2),
                    Text(m.playedAt != null ? 'Heard' : 'Sent',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 11)),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}