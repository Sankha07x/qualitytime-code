import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'uid_generator.dart';

/// Handles login and creates a profile (with a generated UID) on first
/// sign-in. Contacts only ever see the public UID.
class PhoneAuthService {
  final SupabaseClient _client = Supabase.instance.client;

  static const _webClientId =
      '398679981384-cls5ju3m8bsh8ral57i7vgm1n0jo2eqo.apps.googleusercontent.com';
  static bool _googleReady = false;

  /// Real login: Google account -> Supabase user -> profile.
  Future<void> signInWithGoogle() async {
    if (!_googleReady) {
      await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
      _googleReady = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw Exception('Google did not return an ID token');

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    if (response.user != null) {
      await _ensureProfileExists(response.user!.id, account.displayName);
      final meta = response.user!.userMetadata;
      final photo = (meta?['avatar_url'] ?? meta?['picture'])?.toString();
      if (photo != null && photo.isNotEmpty) {
        await _client
            .from('profiles')
            .update({'photo_url': photo}).eq('id', response.user!.id);
      }
    }
  }

  // ---- Old dev login and phone OTP (kept for later) ----

  Future<void> signInAnonymously() async {
    final response = await _client.auth.signInAnonymously();
    if (response.user != null) {
      await _ensureProfileExists(response.user!.id, null);
    }
  }

  Future<void> sendOtp(String phoneNumber) async {
    await _client.auth.signInWithOtp(phone: phoneNumber);
  }

  Future<AuthResponse> verifyOtp(String phoneNumber, String otp) async {
    final response = await _client.auth.verifyOTP(
      phone: phoneNumber,
      token: otp,
      type: OtpType.sms,
    );
    if (response.user != null) {
      await _ensureProfileExists(response.user!.id, null);
    }
    return response;
  }

  // ---- Shared logic ----

  Future<void> _ensureProfileExists(String userId, String? name) async {
    final existing = await _client
        .from('profiles')
        .select('uid')
        .eq('id', userId)
        .maybeSingle();

    if (existing == null) {
      String uid;
      while (true) {
        uid = UidGenerator.generate();
        final clash = await _client
            .from('profiles')
            .select('uid')
            .eq('uid', uid)
            .maybeSingle();
        if (clash == null) break;
      }

      await _client.from('profiles').insert({
        'id': userId,
        'uid': uid,
        'display_name': (name != null && name.isNotEmpty) ? name : uid,
      });
    }
  }

  Future<String?> getMyUid() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final result = await _client
        .from('profiles')
        .select('uid')
        .eq('id', userId)
        .maybeSingle();
    return result?['uid'];
  }

  Future<void> signOut() => _client.auth.signOut();

  bool get isSignedIn => _client.auth.currentUser != null;
  bool get isAnonymous => _client.auth.currentUser?.isAnonymous ?? false;
}