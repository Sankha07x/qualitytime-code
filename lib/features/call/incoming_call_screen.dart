import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/blurred_photo.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/user_avatar.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../utils/settings/app_settings.dart';
import '../../utils/lock_screen.dart';

/// Full-screen Accept / Decline. Pops with true (accept) or false (decline).
class IncomingCallScreen extends StatefulWidget {
  final String callerName;
  final bool video;
  final String? photoUrl;

  const IncomingCallScreen({
    super.key,
    required this.callerName,
    required this.video,
    this.photoUrl,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  Timer? _buzz;
  Timer? _stopSound;
  final _tonePlayer = AudioPlayer();
  bool get _ownSound => AppSettings.incomingTone.value != 'system';

  @override
  void initState() {
    super.initState();
    LockScreen.hold();
    _ring();
    _startSound();
    _stopSound = Timer(const Duration(seconds: 30), () => _tonePlayer.stop());
    _buzz = Timer.periodic(const Duration(seconds: 2), (_) => _ring());
  }

  void _ring() {
    HapticFeedback.vibrate();
    if (!_ownSound) SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _startSound() async {
    if (!_ownSound) return;
    try {
      await _tonePlayer.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationRingtone,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
      await _tonePlayer.setReleaseMode(ReleaseMode.loop);
      final src = AppSettings.incomingSource();
      if (src == null) return;
      await _tonePlayer.play(src, volume: 1.0);
    } catch (_) {}
  }

  @override
  void dispose() {
    _buzz?.cancel();
    _stopSound?.cancel();
    _tonePlayer.stop();
    _tonePlayer.dispose();
    _anim.dispose();
    LockScreen.release();
    super.dispose();
  }

  /// One expanding water-ripple ring around the avatar.
  Widget _ripple(double offset) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final t = (_anim.value + offset) % 1.0;
        final size = 112 + 200 * t;
        return Opacity(
          opacity: (1 - t) * 0.5,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        );
      },
    );
  }

  bool get _hasPhoto =>
      widget.photoUrl != null && widget.photoUrl!.isNotEmpty;

  Widget _letter() => Text(
        widget.callerName.isNotEmpty
            ? widget.callerName[0].toUpperCase()
            : '?',
        style: const TextStyle(
          fontSize: 46,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _avatar() {
    return Container(
      width: 112,
      height: 112,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5EEAD4), Color(0xFF0D9488)],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 20, spreadRadius: 2),
        ],
      ),
      alignment: Alignment.center,
      child: _hasPhoto
          ? CachedNetworkImage(
              imageUrl: hiResPhoto(widget.photoUrl!),
              width: 112,
              height: 112,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorWidget: (_, __, ___) => _letter(),
            )
          : _letter(),
    );
  }

  Widget _action({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool bounce = false,
  }) {
    Widget button = Material(
      color: color,
      elevation: 8,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );

    if (bounce) {
      button = AnimatedBuilder(
        animation: _anim,
        builder: (context, child) => Transform.scale(
          scale: 1 + 0.06 * math.sin(_anim.value * 6 * math.pi),
          child: child,
        ),
        child: button,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0F766E), Color(0xFF042F2E)],
              ),
            ),
          ),
          if (_hasPhoto)
            BlurredPhoto(url: widget.photoUrl!),
          if (_hasPhoto) Container(color: Colors.black45),
          SafeArea(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(
                  offset: Offset(0, 24 * (1 - v)),
                  child: child,
                ),
              ),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  SizedBox(
                    width: 320,
                    height: 320,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _ripple(0.0),
                        _ripple(0.33),
                        _ripple(0.66),
                        _avatar(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.callerName,
                    style: const TextStyle(
                      fontSize: 30,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.video
                        ? 'Incoming video call'
                        : 'Incoming voice call',
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const Spacer(flex: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _action(
                        color: Colors.red,
                        icon: Icons.call_end,
                        label: 'Decline',
                        onTap: () => Navigator.of(context).pop(false),
                      ),
                      _action(
                        color: Colors.green,
                        icon: widget.video ? Icons.videocam : Icons.call,
                        label: 'Accept',
                        bounce: true,
                        onTap: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 64),
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