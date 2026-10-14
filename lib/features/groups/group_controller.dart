import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupModel {
  final String id;
  final String name;
  final bool isOwner;
  final List<String> members;
  final String emoji;
  final int color;
  final String mode; // 'friends' or 'work'
  const GroupModel({
    required this.id,
    required this.name,
    required this.isOwner,
    required this.members,
    this.emoji = '👥',
    this.color = 0xFF0D9488,
    this.mode = 'friends',
  });
}

class GroupController {
  final String myUid;
  final SupabaseClient _c = Supabase.instance.client;
  final groups = ValueNotifier<List<GroupModel>>([]);
  final names = ValueNotifier<Map<String, String>>({});
  RealtimeChannel? _ch;
  bool _disposed = false;

  GroupController(this.myUid);

  String nameOf(String uid) =>
      uid == myUid ? 'You' : (names.value[uid] ?? uid);

  Future<void> start() async {
    await refresh();
    if (_disposed) return;
    _ch = _c
        .channel('groups:$myUid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_members',
          callback: (_) => refresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'groups',
          callback: (_) => refresh(),
        )
        .subscribe();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    try {
      final me = _c.auth.currentUser?.id;
      final rows = await _c
          .from('groups')
          .select(
              'id, name, owner_id, emoji, color, mode, group_members(member_uid)')
          .order('created_at');
      final list = <GroupModel>[];
      final uids = <String>{};
      for (final r in rows as List) {
        final m = [
          for (final x in r['group_members'] as List)
            x['member_uid'] as String,
        ];
        uids.addAll(m);
        list.add(GroupModel(
          id: r['id'] as String,
          name: r['name'] as String,
          isOwner: r['owner_id'] == me,
          members: m,
          emoji: (r['emoji'] ?? '👥').toString(),
          color: (r['color'] as num?)?.toInt() ?? 0xFF0D9488,
          mode: (r['mode'] ?? 'friends').toString(),
        ));
      }
      if (uids.isNotEmpty) {
        final ps = await _c
            .from('profiles')
            .select('uid, display_name')
            .inFilter('uid', uids.toList());
        names.value = {
          for (final p in ps as List)
            p['uid'] as String: (p['display_name'] ?? p['uid']).toString(),
        };
      }
      if (!_disposed) groups.value = list;
    } catch (e) {
      debugPrint('Groups refresh failed: $e');
    }
  }

  /// Returns an error text, or null on success.
  Future<String?> create(
    String name,
    List<String> uids, {
    String emoji = '👥',
    int color = 0xFF0D9488,
    String mode = 'friends',
  }) async {
    try {
      final r = await _c
          .from('groups')
          .insert({
            'name': name.trim(),
            'emoji': emoji,
            'color': color,
            'mode': mode,
          })
          .select('id')
          .single();
      if (uids.isNotEmpty) {
        await _c.from('group_members').insert([
          for (final u in uids) {'group_id': r['id'], 'member_uid': u},
        ]);
      }
      await refresh();
      return null;
    } catch (e) {
      debugPrint('Group create failed: $e');
      return 'Could not create the group.';
    }
  }

  /// Makes a group for a call that started as a 1-to-1 call.
  /// Returns the new group id, or null if it failed.
  Future<String?> createForCall(String name, List<String> uids) async {
    try {
      final r = await _c
          .from('groups')
          .insert({
            'name': name.trim(),
            'emoji': '📞',
            'color': 0xFF0D9488,
            'mode': 'friends',
          })
          .select('id')
          .single();
      final id = r['id'] as String;
      await _c.from('group_members').insert([
        for (final u in uids) {'group_id': id, 'member_uid': u},
      ]);
      await refresh();
      return id;
    } catch (e) {
      debugPrint('Group for call failed: $e');
      return null;
    }
  }

  Future<String?> addMembers(String gid, List<String> uids) async {
    if (uids.isEmpty) return null;
    try {
      await _c.from('group_members').insert([
        for (final u in uids) {'group_id': gid, 'member_uid': u},
      ]);
      await refresh();
      return null;
    } catch (e) {
      debugPrint('Add members failed: $e');
      return 'Could not add them.';
    }
  }

  Future<void> removeMember(String gid, String uid) async {
    try {
      await _c
          .from('group_members')
          .delete()
          .eq('group_id', gid)
          .eq('member_uid', uid);
    } catch (e) {
      debugPrint('Remove member failed: $e');
    }
    await refresh();
  }

  Future<void> deleteGroup(String gid) async {
    try {
      await _c.from('groups').delete().eq('id', gid);
    } catch (e) {
      debugPrint('Delete group failed: $e');
    }
    await refresh();
  }

  void dispose() {
    _disposed = true;
    _ch?.unsubscribe();
    groups.dispose();
    names.dispose();
  }
}