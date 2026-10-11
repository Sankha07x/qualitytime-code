/// Abstract signaling contract. Any backend (Supabase today, something else
/// later) implements this — the rest of the app never talks to Supabase
/// directly, only through this interface, so the backend is swappable.
abstract class SignalingInterface {
  /// Join (or create) a call session channel identified by [sessionId].
  Future<void> joinSession(String sessionId);

  /// Leave the current call session and clean up the channel.
  Future<void> leaveSession();

  /// Send an SDP offer/answer to the other peer in the session.
  Future<void> sendSessionDescription(Map<String, dynamic> description);

  /// Send an ICE candidate to the other peer.
  Future<void> sendIceCandidate(Map<String, dynamic> candidate);

  /// Stream of SDP offers/answers received from the other peer.
  Stream<Map<String, dynamic>> get onSessionDescription;

  /// Stream of ICE candidates received from the other peer.
  Stream<Map<String, dynamic>> get onIceCandidate;

  /// Fires when the other peer joins or leaves the session.
  Stream<bool> get onPeerPresenceChanged;
}
