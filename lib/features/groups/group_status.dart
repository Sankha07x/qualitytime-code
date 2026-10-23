import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live group calls and unread group-chat counts, shared by the screens.
class GroupStatus {
  GroupStatus._();

  static final live = ValueNotifier<Map<String, bool>>({});
  static final unread = ValueNotifier<Map<String, int>>({});
  static bool _busy = false;

  static Future<void> refresh(String myUid) async {
    if (_busy) return;
    _busy = true;
    try {
      final c = Supabase.instance.client;
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 45))
          .toIso8601String();
      final liveRows = await c
          .from('live_group_calls')
          .select('group_id, video')
          .gte('updated_at', since);
      live.value = {
        for (final r in liveRows as List)
          r['group_id'].toString(): r['video'] == true,
      };

      final p = await SharedPreferences.getInstance();
      await p.reload();
      final now = DateTime.now().millisecondsSinceEpoch;
      var base = p.getInt('gread_base');
      if (base == null) {
        base = now;
        await p.setInt('gread_base', now);
      }
      final rows = await c
          .from('group_messages')
          .select('group_id, created_at')
          .neq('from_uid', myUid)
          .order('created_at', ascending: false)
          .limit(300);
      final counts = <String, int>{};
      for (final r in rows as List) {
        final gid = r['group_id'].toString();
        final seen = p.getInt('gread_$gid') ?? base;
        final t = DateTime.parse(r['created_at'].toString())
            .millisecondsSinceEpoch;
        if (t > seen) counts[gid] = (counts[gid] ?? 0) + 1;
      }
      unread.value = counts;
    } catch (e) {
      debugPrint('GROUP STATUS failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// The group chat was seen: clear its unread count.
  static Future<void> markRead(String gid) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('gread_$gid', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
    if (unread.value.containsKey(gid)) {
      final m = {...unread.value}..remove(gid);
      unread.value = m;
    }
  }
}