import '../../config/app_config.dart';

/// ICE server list used by every RTCPeerConnection in the app.
/// STUN discovers each device's public address; TURN is only used as a
/// fallback relay when a direct P2P path can't be established (strict NATs).
class IceConfig {
  static Map<String, dynamic> get configuration => {
        'iceServers': [
          {
            'urls': ['stun:stun.l.google.com:19302'],
          },
          {
            'urls': AppConfig.turnUrls,
            'username': AppConfig.turnUsername,
            'credential': AppConfig.turnCredential,
          },
        ],
        'sdpSemantics': 'unified-plan',
      };
}