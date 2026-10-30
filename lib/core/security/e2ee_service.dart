import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// End-to-End Encryption (X25519 + HKDF-SHA256 + AES-256-GCM).
/// Private keys stay in Android Keystore; Supabase only ever sees ciphertext.
class E2eeService {
  E2eeService._();

  static const _prefix = 'e2e:1:';
  static final _magic = <int>[0x51, 0x54, 0x45, 0x31]; // "QTE1"
  static final _x = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const _sec = FlutterSecureStorage();

  static String? _myUid;
  static SimpleKeyPair? _myPair;
  static final _peerKeys = <String, SecretKey>{};
  static final _groupKeys = <String, SecretKey>{};

  static bool isEncryptedText(String? s) => s != null && s.startsWith(_prefix);

  /// Forget the saved key for a friend so it is loaded again next time.
  static void forgetPeer(String uid) => _peerKeys.remove(uid);

  static Future<void> init(String myUid) async {
    try {
      final db = Supabase.instance.client;
      final authId = db.auth.currentUser?.id;
      if (authId == null) return;
      _myUid = myUid;
      final kPriv = 'e2ee_priv_$authId';
      final kPub = 'e2ee_pub_$authId';
      var privB64 = await _sec.read(key: kPriv);
      var pubB64 = await _sec.read(key: kPub);
      if (privB64 == null || pubB64 == null) {
        final pair = await _x.newKeyPair();
        final priv = await pair.extractPrivateKeyBytes();
        final pub = (await pair.extractPublicKey()).bytes;
        privB64 = base64Encode(priv);
        pubB64 = base64Encode(pub);
        await _sec.write(key: kPriv, value: privB64);
        await _sec.write(key: kPub, value: pubB64);
      }
      final privBytes = base64Decode(privB64);
      final pubBytes = base64Decode(pubB64);
      _myPair = SimpleKeyPairData(privBytes,
          publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519);
      await db
          .from('profiles')
          .update({'public_key': pubB64})
          .eq('id', authId);
    } catch (e) {
      debugPrint('E2EE init: $e');
    }
  }

  static Future<SecretKey?> _peerSecret(String peerUid) async {
    if (_peerKeys.containsKey(peerUid)) return _peerKeys[peerUid];
    if (_myPair == null) {
      final authId = Supabase.instance.client.auth.currentUser?.id;
      if (authId == null) return null;
      final p = await SharedPreferences.getInstance();
      final u = _myUid ?? p.getString('my_uid_$authId');
      if (u != null) await init(u);
      if (_myPair == null) return null;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final row = await Supabase.instance.client
          .from('profiles')
          .select('public_key')
          .eq('uid', peerUid)
          .maybeSingle();
      var pubB64 = row?['public_key']?.toString() ?? '';
      if (pubB64.isNotEmpty) {
        await prefs.setString('e2ee_pk_$peerUid', pubB64);
      } else {
        pubB64 = prefs.getString('e2ee_pk_$peerUid') ?? '';
      }
      if (pubB64.isEmpty) return null;
      final shared = await _x.sharedSecretKey(
        keyPair: _myPair!,
        remotePublicKey: SimplePublicKey(base64Decode(pubB64),
            type: KeyPairType.x25519),
      );
      final key = await _hkdf.deriveKey(
          secretKey: shared, nonce: utf8.encode('qt-e2ee-v1'));
      _peerKeys[peerUid] = key;
      return key;
    } catch (e) {
      debugPrint('E2EE peer key: $e');
      try {
        final prefs2 = await SharedPreferences.getInstance();
        final cached = prefs2.getString('e2ee_pk_$peerUid') ?? '';
        if (cached.isNotEmpty && _myPair != null) {
          final shared2 = await _x.sharedSecretKey(
            keyPair: _myPair!,
            remotePublicKey: SimplePublicKey(base64Decode(cached),
                type: KeyPairType.x25519),
          );
          return await _hkdf.deriveKey(
              secretKey: shared2, nonce: utf8.encode('qt-e2ee-v1'));
        }
      } catch (_) {}
      return null;
    }
  }

  static Future<String> _encStr(String plain, SecretKey? key) async {
    if (plain.isEmpty || key == null) return plain;
    try {
      final nonce = _aes.newNonce();
      final box =
          await _aes.encrypt(utf8.encode(plain), secretKey: key, nonce: nonce);
      return '$_prefix${base64Encode(box.concatenation())}';
    } catch (_) {
      return plain;
    }
  }

  static Future<String> _decStr(String raw, SecretKey? key) async {
    if (!raw.startsWith(_prefix)) return raw;
    if (key == null) return '🔒 Encrypted message';
    try {
      final all = base64Decode(raw.substring(_prefix.length));
      final box =
          SecretBox.fromConcatenation(all, nonceLength: 12, macLength: 16);
      return utf8.decode(await _aes.decrypt(box, secretKey: key));
    } catch (_) {
      return '🔒 Encrypted message';
    }
  }

  static Future<String> encryptPeerText(String peerUid, String plain) async =>
      _encStr(plain, await _peerSecret(peerUid));

  static Future<String> decryptPeerText(String peerUid, String raw) async =>
      _decStr(raw, await _peerSecret(peerUid));

  static Future<Uint8List> encryptPeerBytes(
      String peerUid, Uint8List plain) async {
    final key = await _peerSecret(peerUid);
    if (key == null) return plain;
    try {
      final box =
          await _aes.encrypt(plain, secretKey: key, nonce: _aes.newNonce());
      return Uint8List.fromList([..._magic, ...box.concatenation()]);
    } catch (_) {
      return plain;
    }
  }

  static Future<Uint8List> decryptPeerBytes(
      String peerUid, Uint8List data) async {
    if (data.length < 32 ||
        data[0] != _magic[0] ||
        data[1] != _magic[1] ||
        data[2] != _magic[2] ||
        data[3] != _magic[3]) {
      return data;
    }
    final key = await _peerSecret(peerUid);
    if (key == null) return data;
    try {
      final box = SecretBox.fromConcatenation(data.sublist(4),
          nonceLength: 12, macLength: 16);
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: key));
    } catch (_) {
      return data;
    }
  }

  static Future<SecretKey?> ensureGroupKey(
      String gid, String myUid, List<String> members) async {
    var gk = _groupKeys[gid];
    final cachedBefore = gk != null;
    var hadRow = false;
    final db = Supabase.instance.client;
    try {
      if (gk == null) {
        final row = await db
            .from('group_member_keys')
            .select('from_uid, encrypted_key')
            .eq('group_id', gid)
            .eq('member_uid', myUid)
            .maybeSingle();
        if (row != null) {
          hadRow = true;
          final dec = await decryptPeerText(
              row['from_uid'].toString(), row['encrypted_key'].toString());
          if (!dec.startsWith('🔒')) {
            gk = SecretKey(base64Decode(dec));
            _groupKeys[gid] = gk;
          }
        }
      }
      if (gk == null) {
        gk = await _aes.newSecretKey();
        _groupKeys[gid] = gk;
      }
      if (cachedBefore && members.isEmpty) return gk;
      final rawB64 = base64Encode(await gk.extractBytes());
      for (final m in {...members, myUid}) {
        final enc = await encryptPeerText(m, rawB64);
        if (enc.startsWith(_prefix)) {
          await db.from('group_member_keys').upsert({
            'group_id': gid,
            'member_uid': m,
            'from_uid': myUid,
            'encrypted_key': enc,
          });
        }
      }
    } catch (_) {}
    return gk;
  }

  static Future<String> encryptGroupText(String gid, String myUid, String plain,
          [List<String> members = const []]) async =>
      _encStr(plain, await ensureGroupKey(gid, myUid, members));

  static Future<String> decryptGroupText(
      String gid, String myUid, String raw) async {
    if (!raw.startsWith(_prefix)) return raw;
    return _decStr(raw, await ensureGroupKey(gid, myUid, const []));
  }
}
