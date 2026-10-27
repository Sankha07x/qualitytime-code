import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/media_compress.dart';

class MyProfile {
  final String uid;
  final String name;
  final String? photoUrl;
  final bool uidChanged;

  const MyProfile({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.uidChanged = false,
  });

  MyProfile copyWith({String? name, String? photoUrl, bool clearPhoto = false}) =>
      MyProfile(
        uid: uid,
        name: name ?? this.name,
        photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
        uidChanged: uidChanged,
      );
}

/// Reads and edits the signed-in user's own profile.
class ProfileService {
  final SupabaseClient _c = Supabase.instance.client;

  String? get _id => _c.auth.currentUser?.id;

    Future<MyProfile?> load() async {
    final id = _id;
    if (id == null) return null;
    final key = 'profile_cache_$id';
    try {
      final r = await _c
          .from('profiles')
          .select('uid, display_name, photo_url, uid_changed')
          .eq('id', id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (r == null) return null;
      final photo = (r['photo_url'] ?? '').toString();
      final p = MyProfile(
        uid: r['uid'] as String,
        name: (r['display_name'] ?? r['uid']).toString(),
        photoUrl: photo.isEmpty ? null : photo,
        uidChanged: r['uid_changed'] == true,
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          key,
          jsonEncode({
            'uid': p.uid,
            'name': p.name,
            'photo': photo,
            'changed': p.uidChanged,
          }),
        );
      } catch (_) {}
      return p;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) rethrow;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final photo = (m['photo'] ?? '').toString();
      return MyProfile(
        uid: m['uid'] as String,
        name: m['name'] as String,
        photoUrl: photo.isEmpty ? null : photo,
        uidChanged: m['changed'] == true,
      );
    }
  }

  Future<void> updateName(String name) async {
    final id = _id;
    if (id == null) return;
    await _c.from('profiles').update({'display_name': name}).eq('id', id);
  }

  Future<String> uploadPhoto(Uint8List bytes) async {
    final id = _id!;
    final sendBytes = await MediaCompress.compressAvatarBytes(bytes);
    final path = '$id/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
    final bucket = _c.storage.from('avatars');
    await bucket.uploadBinary(
      path,
      sendBytes,
      fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
    );
    final url = bucket.getPublicUrl(path);
    await _c.from('profiles').update({'photo_url': url}).eq('id', id);
    // best effort: delete older photos of this user
    try {
      final files = await bucket.list(path: id);
      final old = [
        for (final f in files)
          if ('$id/${f.name}' != path) '$id/${f.name}',
      ];
      if (old.isNotEmpty) await bucket.remove(old);
    } catch (_) {}
    return url;
  }

  Future<void> removePhoto() async {
    final id = _id;
    if (id == null) return;
    await _c.from('profiles').update({'photo_url': null}).eq('id', id);
    try {
      final bucket = _c.storage.from('avatars');
      final files = await bucket.list(path: id);
      final all = [for (final f in files) '$id/${f.name}'];
      if (all.isNotEmpty) await bucket.remove(all);
    } catch (_) {}
  }

  static String? validateUid(String v) {
    if (v.length < 3 || v.length > 20) return 'Use 3 to 20 characters.';
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(v)) {
      return 'Use only a-z, 0-9, - and _.';
    }
    return null;
  }

  /// Changes the public ID (allowed once). Returns an error text, or null.
  Future<String?> changeUid(String raw) async {
    final id = _id;
    if (id == null) return 'Not signed in.';
    final v = raw.trim().toLowerCase();
    final bad = validateUid(v);
    if (bad != null) return bad;
    final me = await load();
    if (me == null) return 'Profile not found.';
    if (me.uidChanged) return 'You already changed your ID once.';
    if (me.uid == v) return 'That is already your ID.';
    final clash =
        await _c.from('profiles').select('uid').eq('uid', v).maybeSingle();
    if (clash != null) return 'That ID is taken.';
    try {
      await _c
          .from('profiles')
          .update({'uid': v, 'uid_changed': true}).eq('id', id);
    } catch (_) {
      return 'Could not change the ID. Try another one.';
    }
    return null;
  }
}
