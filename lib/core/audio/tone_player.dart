import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../../utils/settings/app_settings.dart';

enum _Tone { none, ringback, busy }

/// Plays the caller's ringback tone and the busy tone. Never throws.
class TonePlayer {
  final AudioPlayer _player = AudioPlayer();
  _Tone _current = _Tone.none;
  Timer? _busyTimer;

  /// Ringing sound until the call connects.
  /// [earpiece] = true for voice calls (sound comes from the ear speaker).
  Future<void> playRingback({bool earpiece = false}) async {
    try {
      _busyTimer?.cancel();
      _current = _Tone.ringback;
      await _player.setAudioContext(
        AudioContextConfig(
          route: earpiece
              ? AudioContextConfigRoute.earpiece
              : AudioContextConfigRoute.speaker,
        ).build(),
      );
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AppSettings.ringbackSource(), volume: 0.7);
    } catch (e) {
      debugPrint('TONE: ringback failed: $e');
    }
  }

  /// Short busy tone (about 3 seconds), used when the call is declined.
  Future<void> playBusy() async {
    try {
      _busyTimer?.cancel();
      _current = _Tone.busy;
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/busy.wav'), volume: 0.7);
      _busyTimer = Timer(const Duration(seconds: 3), stop);
    } catch (e) {
      debugPrint('TONE: busy failed: $e');
    }
  }

  /// Stops the ringback only. A busy tone keeps playing until it times out.
  Future<void> stopRingback() async {
    if (_current == _Tone.ringback) await stop();
  }

  Future<void> stop() async {
    try {
      _busyTimer?.cancel();
      _current = _Tone.none;
      await _player.stop();
    } catch (e) {
      debugPrint('TONE: stop failed: $e');
    }
  }

  Future<void> dispose() async {
    _busyTimer?.cancel();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
