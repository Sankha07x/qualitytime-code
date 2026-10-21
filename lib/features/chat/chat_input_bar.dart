import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/glass.dart';
import '../../utils/settings/app_settings.dart';
import '../voice/voice_service.dart';

/// Bottom bar: paperclip, text box, and mic (becomes send when typing).
class ChatInputBar extends StatefulWidget {
  final VoiceService voice;
  final Future<String?> Function(String text) onSendText;
  final VoidCallback onAttach;
  final VoidCallback onRecordStart;
  final void Function(String) onMessage;
  final void Function(bool typing)? onTyping;

  const ChatInputBar({
    super.key,
    required this.voice,
    required this.onSendText,
    required this.onAttach,
    required this.onRecordStart,
    required this.onMessage,
    this.onTyping,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _ctrl = TextEditingController();
  final _level = ValueNotifier<double>(0);
  bool _recording = false;
  bool _sending = false;
  bool _hasText = false;
  int _secs = 0;
  Timer? _timer;
  StreamSubscription? _amp;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final h = _ctrl.text.trim().isNotEmpty;
      widget.onTyping?.call(h);
      if (h != _hasText) setState(() => _hasText = h);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amp?.cancel();
    if (_recording) widget.voice.cancelRecording();
    _ctrl.dispose();
    _level.dispose();
    super.dispose();
  }

  String _fmt(int v) => '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';

  static const _quick = ['Call me later', 'OK 👍', 'Thanks', "Can't talk now", 'On my way'];

  Widget _quickReplies() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6),
        itemCount: _quick.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ActionChip(
          label: Text(_quick[i]),
          onPressed: () async {
            final err = await widget.onSendText(_quick[i]);
            if (err != null && mounted) widget.onMessage(err);
          },
        ),
      ),
    );
  }

  Future<void> _sendText() async {
    final t = _ctrl.text;
    if (t.trim().isEmpty) return;
    _ctrl.clear();
    final err = await widget.onSendText(t);
    if (err != null && mounted) {
      _ctrl.text = t;
      widget.onMessage(err);
    }
  }

  Future<void> _startRec() async {
    widget.onRecordStart();
    if (!await widget.voice.startRecording()) {
      widget.onMessage('Microphone permission is needed.');
      return;
    }
    HapticFeedback.mediumImpact();
    _secs = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secs++);
      if (_secs >= VoiceService.maxSeconds) _finish(true);
    });
    _amp = widget.voice.amplitude(const Duration(milliseconds: 120)).listen((a) {
      _level.value = ((a.current + 50) / 50).clamp(0.0, 1.0);
    });
    setState(() => _recording = true);
  }

  Future<void> _finish(bool send) async {
    if (!_recording) return;
    _timer?.cancel();
    _amp?.cancel();
    _level.value = 0;
    setState(() => _recording = false);
    if (!send) {
      await widget.voice.cancelRecording();
      return;
    }
    final r = await widget.voice.stopRecording();
    if (r == null) {
      widget.onMessage('Too short. Record for at least a second.');
      return;
    }
    if (mounted) setState(() => _sending = true);
    final err = await widget.voice.send(r.file, r.seconds);
    if (mounted) setState(() => _sending = false);
    if (err != null) {
      widget.onMessage(err);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  Widget _circle(IconData i, VoidCallback? onTap) {
    final accent = Color(AppSettings.accent.value);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withOpacity(0.75), accent],
          ),
          boxShadow: [
            BoxShadow(color: accent.withOpacity(0.4), blurRadius: 12),
          ],
        ),
        child: Icon(i, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _wave() => ValueListenableBuilder<double>(
        valueListenable: _level,
        builder: (context, lv, _) => SizedBox(
          height: 30,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 18; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  height: 4 +
                      lv *
                          24 *
                          (0.35 +
                              0.65 * ((math.sin(i * 0.9 + _secs * 1.7) + 1) / 2)),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Sending voice message...',
                    style: TextStyle(color: s.onSurfaceVariant)),
              ),
            if (!_recording && !_hasText) _quickReplies(),
        Glass(
              blur: 12,
              tint: s.surface,
              opacity: 0.55,
              borderRadius: BorderRadius.circular(32),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _recording
                    ? Row(
                        key: const ValueKey('rec'),
                        children: [
                          IconButton(
                            tooltip: 'Cancel',
                            onPressed: () => _finish(false),
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent, size: 28),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _wave(),
                                Text(
                                  '${_fmt(_secs)} / ${_fmt(VoiceService.maxSeconds)}',
                                  style: TextStyle(
                                      color: s.onSurface,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          _circle(Icons.send_rounded, () => _finish(true)),
                        ],
                      )
                    : Row(
                        key: const ValueKey('idle'),
                        children: [
                          IconButton(
                            tooltip: 'Attach file',
                            onPressed: widget.onAttach,
                            icon: const Icon(Icons.attach_file),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Message',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _hasText
                              ? _circle(Icons.send_rounded, _sendText)
                              : _circle(Icons.mic, _sending ? null : _startRec),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}