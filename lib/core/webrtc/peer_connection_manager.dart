import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../signaling/signaling_interface.dart';
import 'ice_config.dart';
import 'media_stream_manager.dart';
import 'quality_profile.dart';
import 'video_tuning.dart';

enum CallConnectionState { idle, connecting, connected, disconnected, failed }

class PeerConnectionManager {
  final SignalingInterface signaling;
  final MediaStreamManager mediaManager;

  RTCPeerConnection? _peerConnection;
  MediaStream? _remoteStream;

  bool _isCaller = false;
  bool _offerReceived = false;
  bool _gotAnswer = false;
  bool _offering = false;
  RTCRtpSender? _videoSender;
  bool _sharing = false;
  Map<String, dynamic>? _pendingOffer;
  Timer? _readyTimer;
    Timer? _restartTimer;

  // My own cap on what I send, and what the other side asked me to send.
  QualityLevel _sendAudio = QualityLevel.medium;
  QualityLevel _sendVideo = QualityLevel.medium;
  QualityLevel _peerWantsAudio = QualityLevel.extreme;
  QualityLevel _peerWantsVideo = QualityLevel.extreme;

  Timer? _statsTimer;
  int _weakStrikes = 0;
  int _goodStrikes = 0;
  int _lastLost = 0;
  int _lastRecv = 0;

  /// Bytes sent + received on the network path, headers included.
  final dataBytes = ValueNotifier<int>(0);

  /// True when delay or packet loss stays bad for a few seconds.
  final weakNetwork = ValueNotifier<bool>(false);

  /// Becomes true when the other phone pressed End.
  final remoteEnded = ValueNotifier<bool>(false);

  /// Becomes true when a video track arrives from the other phone.
    final remoteVideoAdded = ValueNotifier<bool>(false);

  /// False when the other phone turned its camera off.
  final remoteCameraOn = ValueNotifier<bool>(true);

  /// True while the other phone is sharing its screen.
  final remoteScreenOn = ValueNotifier<bool>(false);

  /// Debug: sent/received video resolution, fps, kbps, codec.
  final debugText = ValueNotifier<String>('');

  /// Video level used when the video choice is Auto.
  final autoVideo = ValueNotifier<QualityLevel>(QualityLevel.medium);
  int _autoGood = 0;
  int _autoBad = 0;
  int _autoUpNeeded = 10;
  int _lastVSent = 0;
  int _lastVRecv = 0;

  final _stateController = ValueNotifier<CallConnectionState>(
    CallConnectionState.idle,
  );
  ValueListenable<CallConnectionState> get state => _stateController;

  final _remoteStreamController = ValueNotifier<MediaStream?>(null);
  ValueListenable<MediaStream?> get remoteStream => _remoteStreamController;

  PeerConnectionManager({required this.signaling, required this.mediaManager});

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(IceConfig.configuration);

    final localStream = mediaManager.localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        final s = await _peerConnection!.addTrack(track, localStream);
        if (track.kind == 'video') _videoSender = s;
      }
    }

    await _preferCodecs();

    _peerConnection!.onIceCandidate = (candidate) {
      final c = candidate.candidate;
      if (c == null || c.isEmpty) return;
      signaling.sendIceCandidate(candidate.toMap());
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        for (final t in _remoteStream!.getAudioTracks()) {
          t.enabled = true;
        }
        if (event.track.kind == 'video') {
          _remoteStreamController.value = null;
          remoteVideoAdded.value = true;
          remoteCameraOn.value = true;
        }
        _remoteStreamController.value = _remoteStream;
      }
    };

    _peerConnection!.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _restartTimer?.cancel();
          _stateController.value = CallConnectionState.connected;
          _applySendQuality();
          _startStats();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _stateController.value = CallConnectionState.disconnected;
          _scheduleIceRestart();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _stateController.value = CallConnectionState.failed;
          _scheduleIceRestart();
          break;
        default:
          break;
      }
    };

    signaling.onSessionDescription.listen(_handleRemoteDescription);
    signaling.onIceCandidate.listen(_handleRemoteIceCandidate);
  }

  /// Caller: waits for the receiver's "ready", then sends the offer.
  Future<void> startCall() async {
    _isCaller = true;
    _stateController.value = CallConnectionState.connecting;
    await _createPeerConnection();
  }

  /// Receiver: keeps saying "ready" until the offer arrives.
  Future<void> waitForCall() async {
    _isCaller = false;
    _stateController.value = CallConnectionState.connecting;
    await _createPeerConnection();

    void sendReady() {
      if (_offerReceived) {
        _readyTimer?.cancel();
        return;
      }
      signaling.sendSessionDescription({'type': 'ready'});
    }

    sendReady();
    _readyTimer = Timer.periodic(const Duration(seconds: 2), (_) => sendReady());
  }

  /// Caller only: if the link drops, re-do ICE so the audio path recovers.
  void _scheduleIceRestart() {
    if (!_isCaller) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(seconds: 3), _restartIce);
  }

  Future<void> _restartIce() async {
    final pc = _peerConnection;
    if (pc == null ||
        _stateController.value == CallConnectionState.connected) {
      return;
    }
    try {
      final offer = await pc.createOffer({'iceRestart': true});
      await pc.setLocalDescription(offer);
      await signaling.sendSessionDescription(
        {'type': 'offer', 'sdp': offer.sdp, 'restart': true},
      );
    } catch (e) {
      debugPrint('ICE restart failed: $e');
    }
    _restartTimer = Timer(const Duration(seconds: 8), _restartIce);
  }

  Future<void> _sendOffer() async {
    if (_gotAnswer) return;
    if (_pendingOffer != null) {
      await signaling.sendSessionDescription(_pendingOffer!);
      return;
    }
    if (_offering) return;
    _offering = true;
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _pendingOffer = {'type': offer.type, 'sdp': offer.sdp};
    await signaling.sendSessionDescription(_pendingOffer!);
  }

  Future<void> _handleRemoteDescription(Map<String, dynamic> data) async {
    final type = data['type'];

    if (type == 'ready') {
      if (_isCaller) await _sendOffer();
      return;
    }

    if (type == 'end') {
      remoteEnded.value = true;
      return;
    }

        if (type == 'camera') {
      remoteCameraOn.value = data['on'] == true;
      return;
    }

    if (type == 'screen') {
      final on = data['on'] == true;
      remoteScreenOn.value = on;
      if (on) remoteCameraOn.value = true;
      return;
    }

    if (type == 'quality') {
      _peerWantsAudio = QualityLevel.values.byName(data['audio'] as String);
      _peerWantsVideo = QualityLevel.values.byName(data['video'] as String);
      await _applySendQuality();
      return;
    }

    if (data['renegotiate'] == true) {
      final pc = _peerConnection;
      if (pc == null) return;
      if (type == 'offer') {
        await pc.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'offer'));
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        await signaling.sendSessionDescription(
          {'type': 'answer', 'sdp': answer.sdp, 'renegotiate': true},
        );
        await _applySendQuality();
      } else if (type == 'answer') {
        await pc.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'answer'));
        await _applySendQuality();
      }
      return;
    }

    if (type == 'offer') {
      if (_isCaller) return;
      if (_offerReceived && data['restart'] != true) return;
      _offerReceived = true;
      _readyTimer?.cancel();
    } else if (type == 'answer') {
      if (!_isCaller) return;
      if (_gotAnswer &&
          _peerConnection?.signalingState !=
              RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        return;
      }
      _gotAnswer = true;
    } else {
      return;
    }

    final description = RTCSessionDescription(data['sdp'], data['type']);
    await _peerConnection?.setRemoteDescription(description);

    if (type == 'offer') {
      await _preferCodecs();
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      await signaling.sendSessionDescription({
        'type': answer.type,
        'sdp': answer.sdp,
      });
    }
  }

  Future<void> _handleRemoteIceCandidate(Map<String, dynamic> data) async {
    final c = data['candidate'];
    if (c == null || c is! String || c.isEmpty) return;
    try {
      await _peerConnection?.addCandidate(
        RTCIceCandidate(c, data['sdpMid'], data['sdpMLineIndex']),
      );
    } catch (e) {
      debugPrint('addCandidate failed: $e');
    }
  }

    /// Adds a camera track to a running call and renegotiates.
  Future<void> addVideo(MediaStreamTrack track, MediaStream stream) async {
    final pc = _peerConnection;
    if (pc == null) return;
    _videoSender = await pc.addTrack(track, stream);
    await _preferCodecs();
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await signaling.sendSessionDescription(
      {'type': 'offer', 'sdp': offer.sdp, 'renegotiate': true},
    );
  }
    
  /// Camera off: send nothing (null). Camera on: send the new track.
  Future<void> replaceVideo(MediaStreamTrack? track) async {
    try {
      await _videoSender?.replaceTrack(track);
      if (track != null) await _applySendQuality();
    } catch (e) {
      debugPrint('replaceVideo failed: $e');
    }
  }
    
  Future<void> sendCamera(bool on) async {
    try {
      await signaling.sendSessionDescription({'type': 'camera', 'on': on});
    } catch (e) {
      debugPrint('sendCamera failed: $e');
    }
  }

  /// Sends [screen] instead of the camera. In a voice-only call it adds a
  /// video line and renegotiates (like the voice -> video upgrade).
  Future<bool> startShare(MediaStreamTrack screen, MediaStream stream) async {
    _sharing = true;
    final pc = _peerConnection;
    if (pc == null) return false;
    try {
      if (_videoSender != null) {
        await _videoSender!.replaceTrack(screen);
        await _applySendQuality();
      } else {
        _videoSender = await pc.addTrack(screen, stream);
        await _preferCodecs();
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await signaling.sendSessionDescription(
          {'type': 'offer', 'sdp': offer.sdp, 'renegotiate': true},
        );
      }
      await signaling.sendSessionDescription({'type': 'screen', 'on': true});
      return true;
    } catch (e) {
      _sharing = false;
      debugPrint('startShare failed: $e');
      return false;
    }
  }

  /// Back to the camera track, or to nothing when [restore] is null.
  Future<void> stopShare(MediaStreamTrack? restore) async {
    _sharing = false;
    try {
      await _videoSender?.replaceTrack(restore);
      if (restore != null) await _applySendQuality();
      await signaling.sendSessionDescription({'type': 'screen', 'on': false});
      if (restore == null) await sendCamera(false);
    } catch (e) {
      debugPrint('stopShare failed: $e');
    }
  }

  Future<void> sendEnd() async {
    try {
      await signaling.sendSessionDescription({'type': 'end'});
    } catch (e) {
      debugPrint('sendEnd failed: $e');
    }
  }

  void _startStats() {
    _statsTimer ??=
        Timer.periodic(const Duration(seconds: 2), (_) => _pollStats());
  }

  num _n(dynamic x) => num.tryParse(x.toString()) ?? 0;

  Future<void> _pollStats() async {
    final pc = _peerConnection;
    if (pc == null) return;
    try {
      final reports = await pc.getStats();
      int bytes = 0;
      int lost = 0;
      int recv = 0;
      double rtt = 0;
      final codecNames = <String, String>{};
      String outCodecId = '', inCodecId = '', limit = '';
      String outRes = '-', inRes = '-';
      num outFps = 0, inFps = 0;
      int vSent = 0, vRecv = 0;
      for (final r in reports) {
        final v = r.values;
        final kind = (v['kind'] ?? v['mediaType'] ?? '').toString();
        if (r.type == 'codec') {
          codecNames[r.id] =
              (v['mimeType'] ?? '').toString().replaceFirst('video/', '');
        } else if (r.type == 'outbound-rtp' && kind == 'video') {
          outRes = '${v['frameWidth'] ?? 0}x${v['frameHeight'] ?? 0}';
          outFps = _n(v['framesPerSecond']);
          vSent = _n(v['bytesSent']).toInt();
          outCodecId = (v['codecId'] ?? '').toString();
          limit = (v['qualityLimitationReason'] ?? '').toString();
        } else if (r.type == 'inbound-rtp' && kind == 'video') {
          inRes = '${v['frameWidth'] ?? 0}x${v['frameHeight'] ?? 0}';
          inFps = _n(v['framesPerSecond']);
          vRecv = _n(v['bytesReceived']).toInt();
          inCodecId = (v['codecId'] ?? '').toString();
        }
        if (r.type == 'candidate-pair' &&
            v['nominated'].toString() == 'true') {
          bytes = (_n(v['bytesSent']) + _n(v['bytesReceived'])).toInt();
          rtt = _n(v['currentRoundTripTime']).toDouble();
        } else if (r.type == 'inbound-rtp') {
          lost += _n(v['packetsLost']).toInt();
          recv += _n(v['packetsReceived']).toInt();
        }
      }
      if (bytes > dataBytes.value) dataBytes.value = bytes;
      final outKbps = ((vSent - _lastVSent) * 8 / 2000).round();
      final inKbps = ((vRecv - _lastVRecv) * 8 / 2000).round();
      _lastVSent = vSent;
      _lastVRecv = vRecv;
      if (vSent > 0 || vRecv > 0) {
        debugText.value =
            'Send $outRes ${outFps.round()}fps ${outKbps}kbps '
            '${codecNames[outCodecId] ?? ''} $limit\n'
            'Recv $inRes ${inFps.round()}fps ${inKbps}kbps '
            '${codecNames[inCodecId] ?? ''}';
      }

      final dLost = lost - _lastLost;
      final dRecv = recv - _lastRecv;
      _lastLost = lost;
      _lastRecv = recv;
      final total = dLost + dRecv;
      final lossRate = total > 0 ? dLost / total : 0.0;

      final bad = rtt > 0.5 || lossRate > 0.08;
      if (bad) {
        _weakStrikes++;
        _goodStrikes = 0;
      } else {
        _goodStrikes++;
        _weakStrikes = 0;
      }
      _updateAuto(bad || limit == 'cpu');
      if (_weakStrikes >= 2) weakNetwork.value = true;
      if (_goodStrikes >= 5) weakNetwork.value = false;
    } catch (e) {
      debugPrint('pollStats failed: $e');
    }
  }

  int _rank(QualityLevel l) =>
      const {'low': 0, 'medium': 1, 'high': 2, 'extreme': 3}[l.name] ?? 1;

  QualityLevel _level(int r) =>
      QualityLevel.values.byName(const ['low', 'medium', 'high', 'extreme'][r]);

  /// Auto video: drop fast on trouble, climb slowly when all is good.
  void _updateAuto(bool bad) {
    final cur = _rank(autoVideo.value);
    if (bad) {
      _autoGood = 0;
      _autoBad++;
      if (_autoBad >= 2 && cur > 0) {
        autoVideo.value = _level(cur - 1);
        _autoBad = 0;
        _autoUpNeeded = _autoUpNeeded * 2 > 60 ? 60 : _autoUpNeeded * 2;
      }
    } else {
      _autoBad = 0;
      _autoGood++;
      if (_autoGood >= _autoUpNeeded && cur < 2) {
        autoVideo.value = _level(cur + 1);
        _autoGood = 0;
      }
    }
  }

  /// Prefer VP9, then VP8, then H.264 for video.
  Future<void> _preferCodecs() async {
    try {
      final pc = _peerConnection;
      if (pc == null) return;
      final caps = await getRtpSenderCapabilities('video');
      final all = caps.codecs ?? [];
      List<RTCRtpCodecCapability> pick(bool Function(String) f) =>
          all.where((c) => f(c.mimeType.toLowerCase())).toList();
      final prefs = [
        ...pick((m) => m.contains('vp9')),
        ...pick((m) => m.contains('vp8')),
        ...pick((m) => m.contains('h264')),
        ...pick((m) => m.contains('av1')),
        ...pick((m) =>
            !m.contains('vp9') &&
            !m.contains('vp8') &&
            !m.contains('h264') &&
            !m.contains('av1')),
      ];
      for (final t in await pc.getTransceivers()) {
        try {
          final kind = t.sender.track?.kind ?? t.receiver.track?.kind;
          if (kind == 'video') await t.setCodecPreferences(prefs);
        } catch (e) {
          debugPrint('codec pref failed: $e');
        }
      }
    } catch (e) {
      debugPrint('preferCodecs failed: $e');
    }
  }

  /// What I send = the lower of my own setting and what the other side asked.
  Future<void> _applySendQuality() async {
    final pc = _peerConnection;
    if (pc == null) return;
    final audio = lowerOf(_sendAudio, _peerWantsAudio);
    final video = lowerOf(_sendVideo, _peerWantsVideo);
    try {
      for (final sender in await pc.getSenders()) {
        final kind = sender.track?.kind;
        final params = sender.parameters;
        final encodings = params.encodings;
        if (encodings == null || encodings.isEmpty) continue;
        for (final enc in encodings) {
          if (kind == 'audio') {
            enc.maxBitrate = QualityProfile.audioBitrate(audio);
          } else if (kind == 'video') {
            enc.active = true;
            enc.maxBitrate = VideoTuning.maxBitrate(video);
            enc.minBitrate = VideoTuning.minBitrate(video);
            final fps = VideoTuning.fps(video);
            enc.maxFramerate = _sharing && fps > 30 ? 30 : fps;
            enc.scaleResolutionDownBy =
                _sharing || video == QualityLevel.extreme
                    ? VideoTuning.scale(video)
                    : VideoTuning.scale(video) *
                        (mediaManager.extremeCapture ? 1.5 : 1.0);
          }
        }
        await sender.setParameters(params);
      }
    } catch (e) {
      debugPrint('applySendQuality failed: $e');
    }
  }

  /// My own cap on what I send (the screen buttons call this).
  Future<void> setSendQuality({QualityLevel? audio, QualityLevel? video}) async {
    if (audio != null) _sendAudio = audio;
    if (video != null) _sendVideo = video;
    await _applySendQuality();
  }

  /// Ask the other phone to send me this quality.
  Future<void> requestReceiveQuality({
    required QualityLevel audio,
    required QualityLevel video,
  }) {
    return signaling.sendSessionDescription({
      'type': 'quality',
      'audio': audio.name,
      'video': video.name,
    });
  }

  Future<void> endCall() async {
    _readyTimer?.cancel();
    _restartTimer?.cancel();
    _statsTimer?.cancel();
    _statsTimer = null;
    await _peerConnection?.close();
    await _peerConnection?.dispose();
    _peerConnection = null;
    _remoteStream = null;
    _remoteStreamController.value = null;
    _stateController.value = CallConnectionState.idle;
  }

  void dispose() {
    endCall();
    _stateController.dispose();
    _remoteStreamController.dispose();
    dataBytes.dispose();
    weakNetwork.dispose();
    remoteEnded.dispose();
    remoteVideoAdded.dispose();
    remoteCameraOn.dispose();
    remoteScreenOn.dispose();
    debugText.dispose();
    autoVideo.dispose();
  }
}