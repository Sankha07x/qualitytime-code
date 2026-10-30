import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'contact_model.dart';

/// Contacts are kept on the phone (fast, works offline) and mirrored to the
/// Supabase `contacts` table, which only the owner can read (row-level
/// security). After a reinstall or on a new phone, [syncWithCloud] brings
/// them back.
class ContactController {
  static const _prefsKey = 'contacts_v1';
  final SupabaseClient _client = Supabase.instance.client;
  bool _disposed = false;

  final _contactsController = ValueNotifier<List<ContactModel>>([]);
  ValueListenable<List<ContactModel>> get contacts => _contactsController;

  ContactController() {
    _load();
  }

  String? get _ownerId => _client.auth.currentUser?.id;

  Map<String, dynamic> _toRow(ContactModel c, String owner) => {
        'owner_id': owner,
        'contact_uid': c.uid,
        'display_name': c.displayName,
        'is_favorite': c.isFavorite,
        'added_at': c.addedAt.toUtc().toIso8601String(),
      };

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || _disposed) return;
      final saved = (jsonDecode(raw) as List)
          .map((e) => ContactModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // keep anything added before loading finished
      for (final c in _contactsController.value) {
        if (!saved.any((s) => s.uid == c.uid)) saved.add(c);
      }
      _contactsController.value = saved;
    } catch (e) {
      debugPrint('Contacts load failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_contactsController.value.map((c) => c.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Contacts save failed: $e');
    }
  }

  /// Downloads this account's contacts, merges them with the local ones,
  /// and uploads any contact that only exists on this phone. Never throws.
  Future<void> syncWithCloud() async {
    final owner = _ownerId;
    if (owner == null || _disposed) return;
    try {
      final rows =
          await _client.from('contacts').select().eq('owner_id', owner);
      final merged = <ContactModel>[
        for (final r in rows as List)
          ContactModel(
            uid: r['contact_uid'] as String,
            displayName: r['display_name'] as String,
            addedAt: DateTime.parse(r['added_at'] as String).toLocal(),
            isFavorite: r['is_favorite'] == true,
          ),
      ];
      var localOnly = <ContactModel>[
        for (final c in _contactsController.value)
          if (!merged.any((m) => m.uid == c.uid)) c,
      ];
      if (localOnly.isNotEmpty) {
        final found = await _client
            .from('profiles')
            .select('uid')
            .inFilter('uid', localOnly.map((c) => c.uid).toList());
        final alive = {for (final r in found as List) r['uid'] as String};
        localOnly = localOnly.where((c) => alive.contains(c.uid)).toList();
      }
      merged.addAll(localOnly);
      if (_disposed) return;
      _contactsController.value = merged;
      await _save();
      if (localOnly.isNotEmpty) {
        await _client.from('contacts').upsert(
              localOnly.map((c) => _toRow(c, owner)).toList(),
              onConflict: 'owner_id,contact_uid',
            );
      }
    } catch (e) {
      debugPrint('Contacts cloud sync failed: $e');
    }
  }

  Future<void> _pushOne(ContactModel c) async {
    final owner = _ownerId;
    if (owner == null) return;
    try {
      await _client
          .from('contacts')
          .upsert(_toRow(c, owner), onConflict: 'owner_id,contact_uid');
    } catch (e) {
      debugPrint('Contact upload failed: $e');
    }
  }

  Future<void> _deleteOne(String uid) async {
    final owner = _ownerId;
    if (owner == null) return;
    try {
      await _client
          .from('contacts')
          .delete()
          .eq('owner_id', owner)
          .eq('contact_uid', uid);
    } catch (e) {
      debugPrint('Contact delete failed: $e');
    }
  }

  // ---- Profile photos (uid -> url, empty string = no photo) ----

  final photos = ValueNotifier<Map<String, String>>({});
  final _fetching = <String>{};

  Future<String?> fetchPhoto(String uid) async {
    final cached = photos.value[uid];
    if (cached != null) return cached.isEmpty ? null : cached;
    if (!_fetching.add(uid)) return null;
    String url = '';
    try {
      final r = await _client
          .from('profiles')
          .select('photo_url')
          .eq('uid', uid)
          .maybeSingle();
      url = r?['photo_url']?.toString() ?? '';
    } catch (_) {
      Future.delayed(const Duration(seconds: 30), () => _fetching.remove(uid));
      return null;
    }
    _fetching.remove(uid);
    if (_disposed) return null;
    photos.value = {...photos.value, uid: url};
    return url.isEmpty ? null : url;
  }

  /// Fetches the latest name and photo of every saved contact in one request.
  Future<void> refreshProfiles() async {
    if (_disposed) return;
    final uids = _contactsController.value.map((c) => c.uid).toList();
    if (uids.isEmpty) return;
    try {
      final rows = await _client
          .from('profiles')
          .select('uid, display_name, photo_url')
          .inFilter('uid', uids);
      if (_disposed) return;
      final map = {for (final r in rows as List) r['uid'] as String: r};
      final newPhotos = {...photos.value};
      var changed = false;
      final updated = <ContactModel>[];
      for (final c in _contactsController.value) {
        final r = map[c.uid];
        if (r == null) {
          updated.add(c);
          continue;
        }
        newPhotos[c.uid] = (r['photo_url'] ?? '').toString();
        final name = (r['display_name'] ?? '').toString();
        if (name.isNotEmpty && name != c.displayName) {
          final n = ContactModel(
            uid: c.uid,
            displayName: name,
            addedAt: c.addedAt,
            isFavorite: c.isFavorite,
          );
          updated.add(n);
          changed = true;
          _pushOne(n);
        } else {
          updated.add(c);
        }
      }
      photos.value = newPhotos;
      if (changed) {
        _contactsController.value = updated;
        await _save();
      }
    } catch (e) {
      debugPrint('Contacts profile refresh failed: $e');
    }
  }

  Future<Map<String, dynamic>?> lookupUid(String uid) async {
    final result = await _client
        .from('profiles')
        .select('uid, display_name')
        .eq('uid', uid)
        .maybeSingle();
    return result;
  }

  Future<void> addContact(String uid, String displayName) async {
    final current = List<ContactModel>.from(_contactsController.value);
    if (current.any((c) => c.uid == uid)) return;

    final contact = ContactModel(
      uid: uid,
      displayName: displayName,
      addedAt: DateTime.now(),
    );
    current.add(contact);
    _contactsController.value = current;
    await _save();
    _pushOne(contact);
  }

  void removeContact(String uid) {
    final current = List<ContactModel>.from(_contactsController.value)
      ..removeWhere((c) => c.uid == uid);
    _contactsController.value = current;
    _save();
    _deleteOne(uid);
    _unfriend(uid);
  }

  void toggleFavorite(String uid) {
    final current = List<ContactModel>.from(_contactsController.value);
    final index = current.indexWhere((c) => c.uid == uid);
    if (index != -1) {
      current[index].isFavorite = !current[index].isFavorite;
      _contactsController.value = current;
      _save();
      _pushOne(current[index]);
    }
  }

  // ---- Friends ----

  String myUid = '';

  /// The running contact controller (the call screen uses it to add people).
  static ContactController? current;
  final friends = ValueNotifier<Set<String>>({});
  final incoming = ValueNotifier<List<Map<String, String>>>([]);
  final outgoing = ValueNotifier<Set<String>>({});
  final sent = ValueNotifier<List<Map<String, String>>>([]);
  RealtimeChannel? _friendChannel;

  Future<void> startFriends() async {
    if (_disposed || myUid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('friends_v1_$myUid');
      if (saved != null && friends.value.isEmpty) friends.value = saved.toSet();
    } catch (_) {}
    await refreshFriends();
    if (_friendChannel != null || _disposed) return;
    _friendChannel = _client
        .channel('friends:$myUid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friend_requests',
          callback: (_) => refreshFriends(),
        )
        .subscribe();
  }

  Future<void> refreshFriends() async {
    if (_disposed || myUid.isEmpty) return;
    try {
      final rows = await _client
          .from('friend_requests')
          .select()
          .or('from_uid.eq.$myUid,to_uid.eq.$myUid');
      final f = <String>{};
      final inc = <String, String>{};
      final out = <String>{};
      final outIds = <String, String>{};
      for (final r in rows as List) {
        final from = r['from_uid'] as String;
        final to = r['to_uid'] as String;
        if (r['status'] == 'accepted') {
          f.add(from == myUid ? to : from);
        } else if (to == myUid) {
          inc[from] = r['id'].toString();
        } else {
          out.add(to);
          outIds[to] = r['id'].toString();
        }
      }
      final need = <String>{
        ...inc.keys,
        ...outIds.keys,
        ...f.where((u) => !_contactsController.value.any((c) => c.uid == u)),
      };
      final names = <String, String>{};
      if (need.isNotEmpty) {
        final ps = await _client
            .from('profiles')
            .select('uid, display_name, photo_url')
            .inFilter('uid', need.toList());
        final np = {...photos.value};
        for (final p in ps as List) {
          final u = p['uid'] as String;
          names[u] = (p['display_name'] ?? u).toString();
          np[u] = (p['photo_url'] ?? '').toString();
        }
        photos.value = np;
      }
      if (_disposed) return;
      for (final u in f) {
        if (!_contactsController.value.any((c) => c.uid == u)) {
          await addContact(u, names[u] ?? u);
        }
      }
      final gone = friends.value.where((u) => !f.contains(u)).toList();
      if (gone.isNotEmpty) {
        final left = List<ContactModel>.from(_contactsController.value)
          ..removeWhere((c) => gone.contains(c.uid));
        _contactsController.value = left;
        await _save();
        for (final u in gone) {
          _deleteOne(u);
        }
      }
      friends.value = f;
      outgoing.value = out;
      sent.value = [
        for (final e in outIds.entries)
          {'id': e.value, 'uid': e.key, 'name': names[e.key] ?? e.key},
      ];
      incoming.value = [
        for (final e in inc.entries)
          {'id': e.value, 'uid': e.key, 'name': names[e.key] ?? e.key},
      ];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('friends_v1_$myUid', f.toList());
    } catch (e) {
      debugPrint('Friends refresh failed: $e');
    }
  }

  /// Returns an error text, or null on success.
  Future<String?> sendFriendRequest(String uid) async {
    if (uid == myUid) return "That's your own ID.";
    if (friends.value.contains(uid)) return 'You are already friends.';
    if (outgoing.value.contains(uid)) return 'Request already sent.';
    try {
      final inc = incoming.value.where((r) => r['uid'] == uid).firstOrNull;
      if (inc != null) {
        await acceptRequest(inc['id']!);
        return null;
      }
      await _client.from('friend_requests').insert({
        'from_owner': _ownerId,
        'from_uid': myUid,
        'to_uid': uid,
      });
      await refreshFriends();
      return null;
    } catch (e) {
      debugPrint('Friend request failed: $e');
      return 'Could not send the request. Try again.';
    }
  }

  Future<void> acceptRequest(String id) async {
    try {
      await _client
          .from('friend_requests')
          .update({'status': 'accepted'}).eq('id', id);
    } catch (e) {
      debugPrint('Accept failed: $e');
    }
    await refreshFriends();
  }

  Future<void> declineRequest(String id) async {
    try {
      await _client.from('friend_requests').delete().eq('id', id);
    } catch (e) {
      debugPrint('Decline failed: $e');
    }
    await refreshFriends();
  }

  /// Takes back a request I sent.
  Future<void> cancelRequest(String id) async {
    try {
      await _client.from('friend_requests').delete().eq('id', id);
    } catch (e) {
      debugPrint('Cancel failed: $e');
    }
    await refreshFriends();
  }

  /// True if accepted friend. Re-checks the cloud once if not found.
  Future<bool> isFriend(String uid) async {
    if (friends.value.contains(uid)) return true;
    await refreshFriends().timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () {},
    );
    return friends.value.contains(uid);
  }

  Future<void> _unfriend(String uid) async {
    friends.value = {...friends.value}..remove(uid);
    if (myUid.isEmpty) return;
    try {
      await _client.from('friend_requests').delete().or(
          'and(from_uid.eq.$myUid,to_uid.eq.$uid),and(from_uid.eq.$uid,to_uid.eq.$myUid)');
    } catch (e) {
      debugPrint('Unfriend failed: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _friendChannel?.unsubscribe();
    friends.dispose();
    incoming.dispose();
    outgoing.dispose();
    sent.dispose();
    _contactsController.dispose();
    photos.dispose();
  }
}