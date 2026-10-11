import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live online status through Supabase Realtime Presence.
/// Each user announces themselves on channel "presence:<uid>";
/// contacts watch that channel. Nothing is stored in the database.
class PresenceService {
  final String myUid;
  final SupabaseClient _c = Supabase.instance.client;
  RealtimeChannel? _mine;
  bool _visible = true;
  bool _disposed = false;
  final _watch = <String, RealtimeChannel>{};
  final online = ValueNotifier<Set<String>>(<String>{});

  PresenceService(this.myUid);

  void start() {
    final ch = _c.channel('presence:$myUid');
    _mine = ch;
    ch.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed && _visible) {
        await _track();
      }
    });
  }

  Future<void> _track() async {
    try {
      await _mine?.track({'at': DateTime.now().toIso8601String()});
    } catch (e) {
      debugPrint('PRESENCE track: $e');
    }
  }

  /// true = show me as online, false = hide (app in background).
  Future<void> setVisible(bool v) async {
    _visible = v;
    try {
      if (v) {
        await _track();
      } else {
        await _mine?.untrack();
      }
    } catch (_) {}
  }

  /// Watch exactly these contacts (adds new ones, drops removed ones).
  void watch(Iterable<String> uids) {
    if (_disposed) return;
    final want = uids.where((u) => u != myUid).toSet();
    for (final u in _watch.keys.toList()) {
      if (!want.contains(u)) {
        _c.removeChannel(_watch.remove(u)!);
        _set(u, false);
      }
    }
    for (final u in want) {
      if (_watch.containsKey(u)) continue;
      final ch = _c.channel('presence:$u');
      ch.onPresenceSync((_) {
        _set(u, ch.presenceState().isNotEmpty);
      }).subscribe();
      _watch[u] = ch;
    }
  }

  void _set(String u, bool on) {
    if (_disposed) return;
    final cur = online.value;
    if (cur.contains(u) == on) return;
    online.value = on ? {...cur, u} : (Set<String>.from(cur)..remove(u));
  }

  void dispose() {
    _disposed = true;
    for (final ch in _watch.values) {
      _c.removeChannel(ch);
    }
    _watch.clear();
    if (_mine != null) _c.removeChannel(_mine!);
    online.dispose();
  }
}