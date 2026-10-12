import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'fx_bridge.dart';

/// Handles local camera/microphone capture. Video is captured at up to 720p
/// and scaled down per quality level (see quality_profile.dart).
class MediaStreamManager {
  MediaStream? _localStream;
  bool _hasVideo = false;
  bool frontCamera = true;

    void _fxAttach(MediaStreamTrack? t) {
      if (t == null) return;
      FxBridge.applyVideo(trackId: t.id);
    }

  MediaStream? get localStream => _localStream;

  /// True only if a camera track was actually captured.
  bool get hasVideo => _hasVideo;

  static const Map<String, dynamic> _audioConstraints = {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
    'googEchoCancellation': true,
    'googEchoCancellation2': true,
    'googNoiseSuppression': true,
    'googNoiseSuppression2': true,
    'googAutoGainControl': true,
    'googHighpassFilter': true,
    'googTypingNoiseDetection': true,
  };

  /// Requests camera + mic and returns the local media stream.
  /// If the camera can't start (no webcam, busy, permission denied), it
  /// falls back to audio-only so the call still works.
  /// Pass [videoEnabled] = false to start in voice-call-only mode.
Future<MediaStream> getLocalStream({bool videoEnabled = true}) async {
    final s = await _getLocalStreamRaw(videoEnabled: videoEnabled);
    _fxAttach(s.getVideoTracks().firstOrNull);
    FxBridge.applyAudio();
    return s;
  }

  Future<MediaStream> _getLocalStreamRaw({bool videoEnabled = true}) async {
    if (videoEnabled) {
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': _audioConstraints,
          'video': {
            'facingMode': 'user',
            'width': {'ideal': 720},
            'height': {'ideal': 1280},
            'frameRate': {'ideal': 30, 'max': 30},
          },
        });
        _hasVideo = _localStream!.getVideoTracks().isNotEmpty;
        return _localStream!;
      } catch (e) {
        debugPrint('MEDIA: camera unavailable, falling back to audio only: $e');
      }
    }

    // Voice-only path (requested, or fallback after camera failure).
    _hasVideo = false;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': _audioConstraints,
      'video': false,
    });
    return _localStream!;
  }

  /// Toggles the microphone on/off without renegotiating the connection.
  void setMicEnabled(bool enabled) {
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = enabled;
    }
  }

  /// Toggles the camera on/off without renegotiating the connection.
  void setCameraEnabled(bool enabled) {
    for (final track in _localStream?.getVideoTracks() ?? []) {
      track.enabled = enabled;
    }
  }

  /// Camera off: really stops the camera hardware.
  Future<void> releaseCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    for (final t in List.of(stream.getVideoTracks())) {
      try {
        await stream.removeTrack(t);
        await t.stop();
      } catch (e) {
        debugPrint('MEDIA: releaseCamera failed: $e');
      }
    }
  }

  /// Camera on again: opens the camera, returns the new track.
  Future<MediaStreamTrack?> reopenCamera() async {
    final stream = _localStream;
    if (stream == null) return null;
    try {
      final s = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': frontCamera ? 'user' : 'environment',
          'width': {'ideal': 720},
          'height': {'ideal': 1280},
          'frameRate': {'ideal': 30, 'max': 30},
        },
      });
      final track = s.getVideoTracks().first;
await stream.addTrack(track);
      _fxAttach(track);
      return track;
    } catch (e) {
      debugPrint('MEDIA: reopenCamera failed: $e');
      return null;
    }
  }

  /// Switches between front/back camera, if the device has both.
  Future<void> switchCamera() async {
    try {
      final videoTrack = _localStream?.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        await Helper.switchCamera(videoTrack);
        frontCamera = !frontCamera;
      }
    } catch (e) {
      debugPrint('MEDIA: switchCamera failed: $e');
    }
  }

  /// Voice -> video: opens the camera and adds it to the running stream.
  Future<MediaStreamTrack?> addVideoTrack() async {
    if (_localStream == null || _hasVideo) return null;
    try {
      final s = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 720},
          'height': {'ideal': 1280},
          'frameRate': {'ideal': 30, 'max': 30},
        },
      });
      final track = s.getVideoTracks().first;
await _localStream!.addTrack(track);
      _fxAttach(track);
      _hasVideo = true;
      return track;
    } catch (e) {
      debugPrint('MEDIA: addVideoTrack failed: $e');
      return null;
    }
  }

  MediaStream? _screenStream;
  MediaStreamTrack? _screenTrack;
  bool get isSharing => _screenTrack != null;

  /// Starts capturing the screen. [onStopped] runs if the system ends it
  /// (for example the user taps "Stop sharing" in the notification).
  Future<MediaStreamTrack?> startScreen(VoidCallback onStopped) async {
    try {
      final s = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'frameRate': {'ideal': 15, 'max': 24},
        },
        'audio': false,
      });
      final t = s.getVideoTracks().first;
      t.onEnded = onStopped;
      _screenStream = s;
      _screenTrack = t;
      return t;
    } catch (e) {
      debugPrint('MEDIA: startScreen failed: $e');
      return null;
    }
  }

  Future<void> stopScreen() async {
    final s = _screenStream, t = _screenTrack;
    _screenStream = null;
    _screenTrack = null;
    try {
      if (t != null) {
        t.onEnded = null;
        await t.stop();
      }
      await s?.dispose();
    } catch (e) {
      debugPrint('MEDIA: stopScreen failed: $e');
    }
  }

  Future<void> dispose() async {
    await stopScreen();
    try {
      for (final track in _localStream?.getTracks() ?? []) {
        await track.stop();
      }
      await _localStream?.dispose();
    } catch (e) {
      debugPrint('MEDIA: dispose error: $e');
    }
    _localStream = null;
    _hasVideo = false;
  }
}