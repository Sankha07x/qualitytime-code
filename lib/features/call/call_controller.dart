import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/signaling/supabase_signaling.dart';
import '../../core/webrtc/media_stream_manager.dart';
import '../../core/webrtc/peer_connection_manager.dart';
import '../../core/webrtc/quality_choice.dart';
import '../../utils/settings/data_saver_prefs.dart';
import '../../core/notifications/call_notification.dart';
import '../../core/webrtc/screen_share_bridge.dart';
import 'active_call.dart';

enum CallPhase { idle, ringing, connecting, active, ended }

/// Ties MediaStreamManager + PeerConnectionManager + Signaling together into
/// one simple call lifecycle the UI (call_screen.dart) can drive with a
/// handful of method calls and listen to via ValueNotifiers.
class CallController {
  final MediaStreamManager mediaManager = MediaStreamManager();
  late final SupabaseSignaling _signaling;
  late final PeerConnectionManager _peerManager;

  final _phaseController = ValueNotifier<CallPhase>(CallPhase.idle);
  ValueListenable<CallPhase> get phase => _phaseController;

  ValueListenable<MediaStream?> get remoteStream => _peerManager.remoteStream;
  MediaStream? get localStream => mediaManager.localStream;

  ValueListenable<int> get dataBytes => _peerManager.dataBytes;
    ValueListenable<bool> get weakNetwork => _peerManager.weakNetwork;
  ValueListenable<bool> get remoteCameraOn => _peerManager.remoteCameraOn;
  ValueListenable<String> get debugText => _peerManager.debugText;
  ValueListenable<bool> get remoteScreenOn => _peerManager.remoteScreenOn;

  /// True while I am sharing my screen.
  final screenSharing = ValueNotifier<bool>(false);

  /// Listener-side boost for a quiet or faraway speaker.
  final voiceBoost = ValueNotifier<bool>(false);

  void setVoiceBoost(bool on) {
    voiceBoost.value = on;
    _applyBoost();
  }

  void _applyBoost() {
    final s = _peerManager.remoteStream.value;
    if (s == null) return;
    for (final t in s.getAudioTracks()) {
      try {
        Helper.setVolume(voiceBoost.value ? 3.0 : 1.0, t);
      } catch (_) {}
    }
  }

  /// Text shown on the call screen when the call ends.
  String endLabel = 'Call ended';

  /// Name of the other person (set by the call screen).
  String peerName = '';

  /// Remembered so the speaker state survives minimizing the call.
  bool speakerOn = false;

  bool _ongoingStarted = false;

  /// True when the screen is closed quietly (simultaneous-call hand-over).
  bool silentEnd = false;

  DateTime? _connectedAt;
  DateTime? _endedAt;

  /// Seconds the call was connected (0 if it never connected).
  int get connectedSeconds {
    final start = _connectedAt;
    if (start == null) return 0;
    return (_endedAt ?? DateTime.now()).difference(start).inSeconds;
  }

  QualityChoice audioChoice = QualityChoice.auto;
  QualityChoice videoChoice = QualityChoice.auto;

  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool get micEnabled => _micEnabled;
  bool get cameraEnabled => _cameraEnabled;

  CallController() {
    _signaling = SupabaseSignaling();
    _peerManager = PeerConnectionManager(
      signaling: _signaling,
      mediaManager: mediaManager,
    );
    _peerManager.state.addListener(_onConnectionStateChanged);
    _peerManager.remoteStream.addListener(_applyBoost);
    _peerManager.weakNetwork.addListener(_applyQuality);
    _peerManager.remoteEnded.addListener(_onRemoteEnded);
    _peerManager.remoteReady.addListener(_onPeerReady);
    _peerManager.remoteVideoAdded.addListener(_onRemoteVideo);
    _peerManager.autoVideo.addListener(_applyQuality);
    _loadDefaults();
  }

  void _onConnectionStateChanged() {
    switch (_peerManager.state.value) {
      case CallConnectionState.connected:
        _phaseController.value = CallPhase.active;
        _connectedAt ??= DateTime.now();
        _connectGuard?.cancel();
        _startOngoing();
        _applyQuality();
        break;
      case CallConnectionState.failed:
      case CallConnectionState.disconnected:
        _phaseController.value = CallPhase.connecting;
        break;
      default:
        break;
    }
  }

  /// Initiates an outgoing call to [sessionId] (typically the two UIDs
  /// combined, e.g. "myUid_theirUid" sorted, so both sides derive the same
  /// channel name).
  Future<void> startOutgoingCall(String sessionId, {bool video = true}) async {
    _phaseController.value = CallPhase.connecting;
    await mediaManager.getLocalStream(videoEnabled: video);
    await _signaling.joinSession(sessionId);
    await _peerManager.startCall();
  }

  /// Joins an incoming call session and waits for the caller's offer.
  Future<void> acceptIncomingCall(String sessionId, {bool video = true}) async {
    _phaseController.value = CallPhase.connecting;
    await mediaManager.getLocalStream(videoEnabled: video);
    await _signaling.joinSession(sessionId);
    await _peerManager.waitForCall();
    _armConnectGuard(30);
  }

  bool _hasContactDefault = false;

  /// Saved quality for this friend (set before the call starts).
  void applyContactDefaults(QualityChoice audio, QualityChoice video) {
    _hasContactDefault = true;
    audioChoice = audio;
    videoChoice = video;
  }

  Future<void> _loadDefaults() async {
    if (await DataSaverPrefs.isOn() && !_hasContactDefault) {
      audioChoice = QualityChoice.low;
      videoChoice = QualityChoice.low;
    }
  }

  /// My choice limits what I send AND what I ask the other phone to send me.
  void _applyQuality() {
    if (_phaseController.value != CallPhase.active) return;
    final weak = _peerManager.weakNetwork.value;
    final audio = resolveChoice(audioChoice, weak: weak);
    final video = videoChoice == QualityChoice.auto
        ? _peerManager.autoVideo.value
        : resolveChoice(videoChoice, weak: weak);
    _syncCapture();
    _peerManager.setSendQuality(audio: audio, video: video);
    _peerManager.requestReceiveQuality(audio: audio, video: video);
  }

  /// Set when the other phone turned this call into a group call.
  ValueListenable<Map<String, dynamic>?> get groupInvite =>
      _peerManager.groupInvite;

  Future<void> sendGroupInvite(Map<String, dynamic> info) =>
      _peerManager.sendGroupInvite(info);

  /// True once the other phone answered the call.
  bool get peerAnswered => _peerManager.remoteReady.value;

  Timer? _connectGuard;

  /// If the call is still not connected after [seconds], end it cleanly.
  void _armConnectGuard(int seconds) {
    _connectGuard?.cancel();
    _connectGuard = Timer(Duration(seconds: seconds), () {
      final p = _phaseController.value;
      if (p == CallPhase.active || p == CallPhase.ended) return;
      endLabel = 'Could not connect';
      endCall(notifyPeer: true);
    });
  }

  void _onPeerReady() {
    if (_peerManager.remoteReady.value) _armConnectGuard(25);
  }

  bool _captureBusy = false;

  /// Extreme = camera at 1080p 60fps. Any other choice = 720p 30fps.
  Future<void> _syncCapture() async {
    if (_captureBusy || screenSharing.value) return;
    final want = videoChoice == QualityChoice.extreme;
    if (want == mediaManager.extremeCapture) return;
    _captureBusy = true;
    try {
      final t = await mediaManager.recaptureCamera(want);
      if (t != null) await _peerManager.replaceVideo(t);
    } finally {
      _captureBusy = false;
    }
  }

  void setAudioChoice(QualityChoice c) {
    audioChoice = c;
    _applyQuality();
  }

  void setVideoChoice(QualityChoice c) {
    videoChoice = c;
    _applyQuality();
  }

  /// True while I have this call on hold.
  final onHold = ValueNotifier<bool>(false);
  ValueListenable<bool> get remoteOnHold => _peerManager.remoteOnHold;
  ValueListenable<bool> get remoteMicOn => _peerManager.remoteMicOn;

  /// Hold: my mic is cut, I hear nothing, the other phone shows "on hold".
  Future<void> toggleHold() async {
    final hold = !onHold.value;
    onHold.value = hold;
    mediaManager.setMicEnabled(hold ? false : _micEnabled);
    for (final t in _peerManager.remoteStream.value?.getAudioTracks() ?? []) {
      t.enabled = !hold;
    }
    _peerManager.sendHold(hold);
  }

  void toggleMic() {
    _micEnabled = !_micEnabled;
    if (!onHold.value) mediaManager.setMicEnabled(_micEnabled);
    _peerManager.sendMic(_micEnabled);
  }

  Future<void> toggleCamera() async {
    if (screenSharing.value) return; // stop sharing first
    _cameraEnabled = !_cameraEnabled;
    if (_cameraEnabled) {
      final t = await mediaManager.reopenCamera();
      if (t == null) {
        _cameraEnabled = false;
        return;
      }
      await _peerManager.replaceVideo(t);
    } else {
      await _peerManager.replaceVideo(null);
      await mediaManager.releaseCamera();
    }
    _peerManager.sendCamera(_cameraEnabled);
  }

  final videoActive = ValueNotifier<bool>(false);

  void _onRemoteVideo() {
    if (_peerManager.remoteVideoAdded.value) videoActive.value = true;
  }

  /// Voice -> video: opens the camera and renegotiates the call.
  Future<bool> enableVideo() async {
    if (screenSharing.value) return false;
    final track = await mediaManager.addVideoTrack();
    final stream = mediaManager.localStream;
    if (track == null || stream == null) return false;
    _cameraEnabled = true;
    videoActive.value = true;
    await _peerManager.addVideo(track, stream);
    if (_ongoingStarted && _connectedAt != null) {
      CallNotification.startOngoing(
        name: peerName.isEmpty ? 'Call' : peerName,
        video: true,
        since: _connectedAt!,
      );
    }
    _applyQuality();
    return true;
  }

  void _startOngoing() {
    if (_ongoingStarted || _connectedAt == null) return;
    _ongoingStarted = true;
    ActiveCall.running = this;
    CallNotification.startOngoing(
      name: peerName.isEmpty ? 'Call' : peerName,
      video: mediaManager.hasVideo,
      since: _connectedAt!,
    );
  }

  /// Shares the screen instead of the camera. Returns an error text, or null.
  Future<String?> startScreenShare() async {
    if (screenSharing.value) return null;
    if (_phaseController.value != CallPhase.active) {
      return 'Wait until the call connects.';
    }
    final stream = mediaManager.localStream;
    if (stream == null) return 'The call is not ready.';
    if (!await ScreenShareBridge.begin()) {
      return 'Screen sharing was not allowed.';
    }
    final t = await mediaManager.startScreen(() => stopScreenShare());
    if (t == null) {
      await ScreenShareBridge.end();
      return 'Could not start screen sharing.';
    }
    final ok = await _peerManager.startShare(t, stream);
    if (!ok) {
      await mediaManager.stopScreen();
      await ScreenShareBridge.end();
      return 'Could not start screen sharing.';
    }
    screenSharing.value = true;
    return null;
  }

  Future<void> stopScreenShare() async {
    if (!screenSharing.value) return;
    screenSharing.value = false;
    MediaStreamTrack? back;
    if (_cameraEnabled && mediaManager.hasVideo) {
      back = mediaManager.localStream?.getVideoTracks().firstOrNull;
    }
    await mediaManager.stopScreen();
    await ScreenShareBridge.end();
    await _peerManager.stopShare(back);
    _syncCapture();
  }

  Future<void> switchCamera() => mediaManager.switchCamera();

  void _onRemoteEnded() {
    if (_peerManager.remoteEnded.value) {
      _phaseController.value = CallPhase.ended;
    }
  }

  Future<void> endCall({bool notifyPeer = true}) async {
    _endedAt ??= DateTime.now();
    if (screenSharing.value) {
      screenSharing.value = false;
      await mediaManager.stopScreen();
      await ScreenShareBridge.end();
    }
    if (notifyPeer) await _peerManager.sendEnd();
    await _peerManager.endCall();
    await _signaling.leaveSession();
    await mediaManager.dispose();
    if (_ongoingStarted) {
      _ongoingStarted = false;
      CallNotification.stopOngoing();
    }
    if (ActiveCall.running == this) ActiveCall.running = null;
    _phaseController.value = CallPhase.ended;
  }

  void dispose() {
    _peerManager.state.removeListener(_onConnectionStateChanged);
    _peerManager.weakNetwork.removeListener(_applyQuality);
    _peerManager.remoteEnded.removeListener(_onRemoteEnded);
    _peerManager.remoteReady.removeListener(_onPeerReady);
    _connectGuard?.cancel();
    _peerManager.dispose();
    _signaling.dispose();
    _phaseController.dispose();
  }
}
